"""
Nearby healthcare facilities — OSM Overpass + Nominatim.

HN-NEARBY-001: timeout-bounded, cache/fallback-aware, honest degraded responses.
Never fabricates places. Never claims success after provider failure.
"""
from __future__ import annotations

import asyncio
import copy
import logging
import math
import time
from dataclasses import dataclass
from typing import Any

import httpx
from fastapi import APIRouter, Depends, Query

from app.core.config import settings
from app.core.deps import get_current_user
from app.core.log_decorator import LoggedAPIRoute
from app.models.user import User
from app.services.cache_service import CacheService, NEARBY_TTL

logger = logging.getLogger(__name__)
router = APIRouter(route_class=LoggedAPIRoute)

OVERPASS_MIRRORS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
_NOMINATIM_HEADERS = {"User-Agent": "HealthNest/1.0 (health companion app)"}

DEFAULT_LAT = -37.8136
DEFAULT_LNG = 145.2286

_AU_LAT_MIN, _AU_LAT_MAX = -44.0, -10.0
_AU_LNG_MIN, _AU_LNG_MAX = 112.0, 154.0

WALK_SPEED_KMH = 5.0
DRIVE_SPEED_KMH = 30.0

_USER_SAFE_UNAVAILABLE = (
    "Nearby services are temporarily unavailable. Please try again shortly."
)
_USER_SAFE_CACHED = (
    "Showing previously loaded results. Live nearby data is temporarily unavailable."
)
_USER_SAFE_GEOCODE = "Could not geocode the provided location."


def _is_in_australia(lat: float, lng: float) -> bool:
    return _AU_LAT_MIN <= lat <= _AU_LAT_MAX and _AU_LNG_MIN <= lng <= _AU_LNG_MAX


class _LocalNearbyCache:
    """Bounded in-process TTL cache (works when Redis is unavailable)."""

    def __init__(self, max_entries: int = 64) -> None:
        self._max = max_entries
        self._store: dict[str, tuple[float, dict[str, Any]]] = {}

    def get(self, key: str) -> dict[str, Any] | None:
        item = self._store.get(key)
        if item is None:
            return None
        expires_at, value = item
        if time.monotonic() > expires_at:
            self._store.pop(key, None)
            return None
        return copy.deepcopy(value)

    def set(self, key: str, value: dict[str, Any], ttl: int) -> None:
        if len(self._store) >= self._max and key not in self._store:
            oldest = min(self._store.items(), key=lambda kv: kv[1][0])[0]
            self._store.pop(oldest, None)
        self._store[key] = (time.monotonic() + max(ttl, 1), copy.deepcopy(value))

    def clear(self) -> None:
        self._store.clear()


_local_cache = _LocalNearbyCache()


async def _cache_get(key: str) -> dict[str, Any] | None:
    cached = await CacheService.get(key)
    if isinstance(cached, dict):
        return cached
    return _local_cache.get(key)


async def _cache_set(key: str, value: dict[str, Any], ttl: int = NEARBY_TTL) -> None:
    await CacheService.set(key, value, ttl=ttl)
    _local_cache.set(key, value, ttl=ttl)


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(d_lng / 2) ** 2
    )
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _travel_times(km: float) -> dict:
    walk_mins = round((km / WALK_SPEED_KMH) * 60)
    drive_mins = round((km / DRIVE_SPEED_KMH) * 60)
    return {
        "walk_mins": max(walk_mins, 1),
        "drive_mins": max(drive_mins, 1),
    }


def _distance_label(km: float) -> str:
    if km < 1.0:
        return f"{round(km * 1000)} m"
    return f"{km:.1f} km"


@dataclass
class _ProviderResult:
    places: list[dict]
    ok: bool
    timed_out: bool = False
    source: str = "overpass"


async def _geocode(
    postcode: str | None, city: str | None, state: str | None
) -> tuple[float, float, str] | None:
    parts = [p for p in [postcode, city, state, "Australia"] if p]
    q = ", ".join(parts)
    timeout = float(settings.NEARBY_NOMINATIM_TIMEOUT_SECONDS)
    try:
        async with httpx.AsyncClient(
            timeout=timeout, headers=_NOMINATIM_HEADERS
        ) as client:
            resp = await client.get(
                NOMINATIM_URL,
                params={
                    "q": q,
                    "format": "json",
                    "limit": 1,
                    "countrycodes": "au",
                },
            )
            results = resp.json()
            if results:
                r = results[0]
                return float(r["lat"]), float(r["lon"]), r.get("display_name", q)
    except httpx.TimeoutException:
        logger.warning("Nominatim geocode timeout for q=%s", q[:80])
    except Exception as exc:
        logger.warning("Nominatim geocode failed: %s", type(exc).__name__)
    return None


_TYPE_RADIUS = {
    "hospital": 10_000,
    "pharmacy": 5_000,
    "lab": 25_000,
    "gp": 10_000,
    "all": 8_000,
}


def _build_overpass_query(
    lat: float, lng: float, radius: int, facility_type: str
) -> str:
    r = radius
    ql_timeout = int(settings.NEARBY_OVERPASS_QL_TIMEOUT)

    if facility_type == "hospital":
        unions = [
            f'nwr["amenity"~"hospital|clinic"](around:{r},{lat},{lng})',
            f'nwr["healthcare"~"hospital|clinic"](around:{r},{lat},{lng})',
            f'nwr["amenity"="urgent_care"](around:{r},{lat},{lng})',
        ]
    elif facility_type == "pharmacy":
        unions = [
            f'nwr["amenity"="pharmacy"](around:{r},{lat},{lng})',
            f'nwr["healthcare"="pharmacy"](around:{r},{lat},{lng})',
        ]
    elif facility_type == "gp":
        unions = [
            f'nwr["amenity"="doctors"](around:{r},{lat},{lng})',
            f'nwr["healthcare"~"doctor|general_practitioner"](around:{r},{lat},{lng})',
        ]
    else:
        unions = [
            f'nwr["amenity"~"hospital|clinic|pharmacy|doctors"](around:{r},{lat},{lng})',
        ]

    union_str = ";\n  ".join(unions)
    return f"[out:json][timeout:{ql_timeout}];\n(\n  {union_str};\n);\nout center tags;"


async def _fetch_overpass_elements(query: str) -> tuple[list[dict], bool, bool]:
    """
    Returns (elements, ok, timed_out).
    ok=True only when a mirror returned valid JSON containing an elements key.
    """
    per_timeout = float(settings.NEARBY_OVERPASS_TIMEOUT_SECONDS)
    overall = float(settings.NEARBY_OVERPASS_OVERALL_SECONDS)
    started = time.monotonic()
    saw_timeout = False

    for url in OVERPASS_MIRRORS:
        remaining = overall - (time.monotonic() - started)
        if remaining <= 0.5:
            saw_timeout = True
            break
        attempt_timeout = min(per_timeout, remaining)
        try:
            async with httpx.AsyncClient(timeout=attempt_timeout) as client:
                resp = await client.post(url, data={"data": query})
            if resp.status_code != 200 or not resp.text.strip():
                logger.warning("Overpass HTTP %s from %s", resp.status_code, url)
                continue
            try:
                data = resp.json()
            except Exception:
                logger.warning("Overpass invalid JSON from %s", url)
                continue
            if "elements" not in data:
                logger.warning("Overpass missing elements from %s", url)
                continue
            elements = data.get("elements") or []
            if not isinstance(elements, list):
                logger.warning("Overpass malformed elements from %s", url)
                continue
            logger.debug("Overpass OK via %s elements=%d", url, len(elements))
            return elements, True, False
        except httpx.TimeoutException:
            saw_timeout = True
            logger.warning("Overpass timeout via %s (%.1fs)", url, attempt_timeout)
        except Exception as exc:
            logger.warning(
                "Overpass mirror %s failed: %s", url, type(exc).__name__
            )

    logger.error("All Overpass mirrors failed for query: %s", query[:80])
    return [], False, saw_timeout


def _parse_element(
    el: dict, origin_lat: float, origin_lng: float, facility_type: str
) -> dict | None:
    tags = el.get("tags", {})
    name = tags.get("name")
    if not name:
        return None

    if el.get("type") == "node":
        el_lat, el_lng = el.get("lat"), el.get("lon")
    else:
        center = el.get("center", {})
        el_lat, el_lng = center.get("lat"), center.get("lon")

    if el_lat is None or el_lng is None:
        return None

    km = _haversine_km(origin_lat, origin_lng, el_lat, el_lng)
    times = _travel_times(km)

    addr_parts = [
        tags.get("addr:housenumber", ""),
        tags.get("addr:street", ""),
        tags.get("addr:suburb", "") or tags.get("addr:city", ""),
        tags.get("addr:state", ""),
        tags.get("addr:postcode", ""),
    ]
    address = tags.get("addr:full") or ", ".join(p for p in addr_parts if p)

    amenity = tags.get("amenity", "")
    healthcare = tags.get("healthcare", "")
    name_lower = name.lower()

    inferred = facility_type
    if amenity == "pharmacy" or healthcare == "pharmacy":
        inferred = "pharmacy"
    elif amenity == "hospital" or healthcare == "hospital":
        inferred = "hospital"
    elif amenity in ("clinic", "doctors") or healthcare in (
        "clinic",
        "doctor",
        "general_practitioner",
    ):
        inferred = "gp"
    elif (
        healthcare in ("laboratory", "blood_bank")
        or tags.get("healthcare:speciality", "").lower()
        in ("pathology", "laboratory")
        or any(
            kw in name_lower
            for kw in (
                "pathology",
                "collection centre",
                "dorevitch",
                "laverty",
                "healthscope",
                "sonic",
                "clinical labs",
                "sullivan",
                "qml",
            )
        )
    ):
        inferred = "lab"

    return {
        "id": el.get("id"),
        "name": name,
        "type": inferred,
        "lat": el_lat,
        "lng": el_lng,
        "distance_km": round(km, 2),
        "distance_label": _distance_label(km),
        "walk_mins": times["walk_mins"],
        "drive_mins": times["drive_mins"],
        "phone": tags.get("phone") or tags.get("contact:phone"),
        "address": address or None,
        "opening_hours": tags.get("opening_hours"),
        "website": tags.get("website") or tags.get("contact:website"),
        "emergency": tags.get("emergency") == "yes" or amenity == "hospital",
        "wheelchair": tags.get("wheelchair", "unknown"),
    }


_LAB_SEARCH_TERMS = ["pathology", "collection centre", "dorevitch"]


async def _search_labs_nominatim(
    origin_lat: float, origin_lng: float, radius_km: float = 25
) -> _ProviderResult:
    delta = min(radius_km / 111.0, 0.5)
    viewbox = (
        f"{origin_lng - delta},{origin_lat - delta},"
        f"{origin_lng + delta},{origin_lat + delta}"
    )
    seen_ids: set = set()
    places: list[dict] = []
    timeout = float(settings.NEARBY_NOMINATIM_TIMEOUT_SECONDS)
    any_ok = False
    any_timeout = False

    for term in _LAB_SEARCH_TERMS:
        try:
            async with httpx.AsyncClient(
                timeout=timeout, headers=_NOMINATIM_HEADERS
            ) as client:
                resp = await client.get(
                    NOMINATIM_URL,
                    params={
                        "q": term,
                        "format": "json",
                        "limit": 20,
                        "countrycodes": "au",
                        "viewbox": viewbox,
                        "bounded": "1",
                        "extratags": "1",
                        "addressdetails": "1",
                    },
                )
            items = resp.json()
            if not isinstance(items, list):
                continue
            any_ok = True
        except httpx.TimeoutException:
            any_timeout = True
            logger.warning("Nominatim lab search timeout for term '%s'", term)
            continue
        except Exception as exc:
            logger.warning(
                "Nominatim lab search failed for term '%s': %s",
                term,
                type(exc).__name__,
            )
            continue

        for item in items:
            osm_id = item.get("osm_id")
            if not osm_id or osm_id in seen_ids:
                continue
            seen_ids.add(osm_id)
            name = item.get("display_name", "").split(",")[0].strip()
            if not name:
                continue
            try:
                item_lat = float(item["lat"])
                item_lng = float(item["lon"])
            except (KeyError, TypeError, ValueError):
                continue
            km = _haversine_km(origin_lat, origin_lng, item_lat, item_lng)
            if km > radius_km:
                continue
            times = _travel_times(km)
            extra = item.get("extratags") or {}
            addr = item.get("address") or {}
            address_parts = [
                addr.get("road", ""),
                addr.get("suburb")
                or addr.get("town")
                or addr.get("city_district")
                or addr.get("city", ""),
                addr.get("state", ""),
                addr.get("postcode", ""),
            ]
            address = ", ".join(p for p in address_parts if p) or None
            places.append(
                {
                    "id": osm_id,
                    "name": name,
                    "type": "lab",
                    "lat": item_lat,
                    "lng": item_lng,
                    "distance_km": round(km, 2),
                    "distance_label": _distance_label(km),
                    "walk_mins": times["walk_mins"],
                    "drive_mins": times["drive_mins"],
                    "phone": extra.get("phone") or extra.get("contact:phone"),
                    "address": address,
                    "opening_hours": extra.get("opening_hours"),
                    "website": extra.get("website")
                    or extra.get("contact:website"),
                    "emergency": False,
                    "wheelchair": extra.get("wheelchair", "unknown"),
                }
            )

    return _ProviderResult(
        places=places,
        ok=any_ok,
        timed_out=any_timeout and not any_ok,
        source="nominatim",
    )


def _success_payload(
    *,
    results: list[dict],
    facility_type: str,
    origin_lat: float,
    origin_lng: float,
    location_source: str,
    data_source: str,
) -> dict[str, Any]:
    return {
        "results": results,
        "count": len(results),
        "type": facility_type,
        "origin": {"lat": origin_lat, "lng": origin_lng},
        "location_source": location_source,
        "status": "ok",
        "cached": False,
        "data_source": data_source,
        "message": None,
        "error": None,
    }


def _cached_payload(
    cached: dict[str, Any], *, location_source: str
) -> dict[str, Any]:
    out = copy.deepcopy(cached)
    out["location_source"] = location_source
    out["status"] = "cached"
    out["cached"] = True
    out["data_source"] = "cache"
    out["message"] = _USER_SAFE_CACHED
    out["error"] = None
    out["count"] = len(out.get("results") or [])
    return out


def _degraded_payload(
    *,
    facility_type: str,
    origin_lat: float,
    origin_lng: float,
    location_source: str,
    timed_out: bool,
) -> dict[str, Any]:
    return {
        "results": [],
        "count": 0,
        "type": facility_type,
        "origin": {"lat": origin_lat, "lng": origin_lng},
        "location_source": location_source,
        "status": "degraded",
        "cached": False,
        "data_source": None,
        "message": _USER_SAFE_UNAVAILABLE,
        "error": _USER_SAFE_UNAVAILABLE,
        "timed_out": timed_out,
    }


@router.get("/")
async def get_nearby(
    lat: float | None = Query(None),
    lng: float | None = Query(None),
    postcode: str | None = Query(None),
    city: str | None = Query(None),
    state: str | None = Query(None),
    facility_type: str = Query("hospital", alias="type"),
    radius: int | None = Query(None, le=25000),
    current_user: User = Depends(get_current_user),
):
    """
    Find nearby medical facilities.

    status:
      ok       — live provider success
      cached   — provider failed; valid cached results returned
      degraded — provider failed and no usable cache
    """
    if lat is not None and lng is not None and _is_in_australia(lat, lng):
        origin_lat, origin_lng = lat, lng
        location_source = "gps"
    elif postcode or city or state:
        result = await _geocode(postcode, city, state)
        if result:
            origin_lat, origin_lng, _ = result
            location_source = "search"
        else:
            return {
                "results": [],
                "count": 0,
                "status": "degraded",
                "cached": False,
                "error": _USER_SAFE_GEOCODE,
                "message": _USER_SAFE_GEOCODE,
                "location_source": "search",
            }
    elif current_user.postcode:
        result = await _geocode(
            current_user.postcode, current_user.city, current_user.state
        )
        if result:
            origin_lat, origin_lng, _ = result
            location_source = "profile"
        else:
            origin_lat, origin_lng = DEFAULT_LAT, DEFAULT_LNG
            location_source = "default"
    else:
        origin_lat, origin_lng = DEFAULT_LAT, DEFAULT_LNG
        location_source = "default"

    effective_radius = (
        radius
        if radius is not None
        else _TYPE_RADIUS.get(facility_type, 8_000)
    )
    cache_key = (
        f"nearby:{origin_lat:.3f}:{origin_lng:.3f}:"
        f"{facility_type}:{effective_radius}"
    )

    timed_out = False
    provider_ok = False
    results: list[dict] = []
    data_source = "overpass"

    try:
        if facility_type == "lab":
            lab = await _search_labs_nominatim(
                origin_lat, origin_lng, radius_km=effective_radius / 1000
            )
            provider_ok = lab.ok
            timed_out = lab.timed_out
            results = lab.places
            data_source = "nominatim"
        else:
            query = _build_overpass_query(
                origin_lat, origin_lng, effective_radius, facility_type
            )
            overall = float(settings.NEARBY_OVERPASS_OVERALL_SECONDS)
            try:
                elements, provider_ok, timed_out = await asyncio.wait_for(
                    _fetch_overpass_elements(query),
                    timeout=overall + 1.0,
                )
            except asyncio.TimeoutError:
                elements, provider_ok, timed_out = [], False, True
                logger.warning("Overpass overall asyncio wait_for budget exceeded")

            if provider_ok:
                results = [
                    p
                    for p in (
                        _parse_element(
                            el, origin_lat, origin_lng, facility_type
                        )
                        for el in elements
                    )
                    if p is not None
                ]
    except Exception as exc:
        logger.error(
            "get_nearby provider failure type=%s: %s",
            facility_type,
            exc.__class__.__name__,
        )
        provider_ok = False

    if provider_ok:
        results.sort(key=lambda x: x["distance_km"])
        results = results[:30]
        payload = _success_payload(
            results=results,
            facility_type=facility_type,
            origin_lat=origin_lat,
            origin_lng=origin_lng,
            location_source=location_source,
            data_source=data_source,
        )
        cache_body = {
            "results": payload["results"],
            "count": payload["count"],
            "type": payload["type"],
            "origin": payload["origin"],
            "data_source": payload["data_source"],
        }
        await _cache_set(cache_key, cache_body, ttl=NEARBY_TTL)
        return payload

    cached = await _cache_get(cache_key)
    if isinstance(cached, dict) and (cached.get("results") or []):
        return _cached_payload(cached, location_source=location_source)

    return _degraded_payload(
        facility_type=facility_type,
        origin_lat=origin_lat,
        origin_lng=origin_lng,
        location_source=location_source,
        timed_out=timed_out,
    )


@router.get("/geocode")
async def geocode_location(
    postcode: str | None = Query(None),
    city: str | None = Query(None),
    state: str | None = Query(None),
    current_user: User = Depends(get_current_user),
):
    """Convert postcode/city/state to lat/lng coordinates."""
    if not any([postcode, city, state]):
        return {"error": "Provide at least one of: postcode, city, state"}

    result = await _geocode(postcode, city, state)
    if result:
        g_lat, g_lng, label = result
        return {"lat": g_lat, "lng": g_lng, "label": label, "found": True}
    return {
        "found": False,
        "error": "Location not found",
        "status": "degraded",
    }
