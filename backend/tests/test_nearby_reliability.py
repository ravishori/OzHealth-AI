"""HN-NEARBY-001 — Nearby reliability: timeouts, cache fallback, honest degraded."""
from __future__ import annotations

import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from app.api.routes import nearby as nearby_mod
from app.api.routes.nearby import (
    _USER_SAFE_UNAVAILABLE,
    _build_overpass_query,
    _fetch_overpass_elements,
    _is_in_australia,
    _local_cache,
    get_nearby,
)


def _user(**kwargs):
    base = dict(
        id=2,
        email="qa@example.com",
        postcode=None,
        city=None,
        state=None,
    )
    base.update(kwargs)
    return SimpleNamespace(**base)


@pytest.fixture(autouse=True)
def _clear_local_cache():
    _local_cache.clear()
    yield
    _local_cache.clear()


def test_au_bbox_fallback_coords():
    assert _is_in_australia(-37.8136, 145.2286) is True
    assert _is_in_australia(37.4, -122.0) is False


def test_overpass_query_uses_bounded_ql_timeout():
    q = _build_overpass_query(-37.81, 145.22, 10000, "hospital")
    assert "[timeout:" in q


@pytest.mark.asyncio
async def test_overpass_success_returns_elements():
    payload = {"elements": [{"type": "node", "id": 1, "lat": -37.8, "lon": 145.2, "tags": {"name": "Test Hospital", "amenity": "hospital"}}]}
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.text = '{"elements":[]}'
    mock_resp.json.return_value = payload
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    mock_client.post = AsyncMock(return_value=mock_resp)
    with patch("app.api.routes.nearby.httpx.AsyncClient", return_value=mock_client):
        elements, ok, timed_out = await _fetch_overpass_elements("q")
    assert ok is True
    assert timed_out is False
    assert len(elements) == 1


@pytest.mark.asyncio
async def test_overpass_timeout_is_bounded_and_not_ok():
    async def _slow_post(*args, **kwargs):
        raise httpx.TimeoutException("timed out")
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    mock_client.post = AsyncMock(side_effect=_slow_post)
    with patch("app.api.routes.nearby.settings") as mock_settings:
        mock_settings.NEARBY_OVERPASS_TIMEOUT_SECONDS = 0.05
        mock_settings.NEARBY_OVERPASS_OVERALL_SECONDS = 0.2
        with patch("app.api.routes.nearby.httpx.AsyncClient", return_value=mock_client):
            started = asyncio.get_event_loop().time()
            elements, ok, timed_out = await _fetch_overpass_elements("q")
            elapsed = asyncio.get_event_loop().time() - started
    assert ok is False
    assert timed_out is True
    assert elements == []
    assert elapsed < 2.0


@pytest.mark.asyncio
async def test_primary_failure_tries_second_mirror():
    calls = []
    async def _post(url, data=None):
        calls.append(url)
        if "overpass-api.de" in url:
            raise httpx.TimeoutException("primary timeout")
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.text = '{"elements":[]}'
        mock_resp.json.return_value = {"elements": []}
        return mock_resp
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    mock_client.post = AsyncMock(side_effect=_post)
    with patch("app.api.routes.nearby.httpx.AsyncClient", return_value=mock_client):
        elements, ok, timed_out = await _fetch_overpass_elements("q")
    assert ok is True
    assert timed_out is False
    assert len(calls) == 2
    assert "kumi" in calls[1]


@pytest.mark.asyncio
async def test_provider_timeout_returns_cached_when_available():
    cached_body = {
        "results": [{
            "id": 9, "name": "Cached Hospital", "type": "hospital",
            "lat": -37.81, "lng": 145.22, "distance_km": 1.0,
            "distance_label": "1.0 km", "walk_mins": 12, "drive_mins": 3,
            "phone": None, "address": None, "opening_hours": None,
            "website": None, "emergency": True, "wheelchair": "unknown",
        }],
        "count": 1, "type": "hospital",
        "origin": {"lat": -37.813, "lng": 145.229},
        "data_source": "overpass",
    }
    with patch("app.api.routes.nearby._fetch_overpass_elements", new=AsyncMock(return_value=([], False, True))), \
         patch("app.api.routes.nearby._cache_get", new=AsyncMock(return_value=cached_body)):
        resp = await get_nearby(lat=-37.8136, lng=145.2286, postcode=None, city=None, state=None, facility_type="hospital", radius=None, current_user=_user())
    assert resp["status"] == "cached"
    assert resp["cached"] is True
    assert resp["count"] == 1
    assert resp["results"][0]["name"] == "Cached Hospital"
    assert resp["status"] != "ok"


@pytest.mark.asyncio
async def test_provider_failure_no_cache_is_degraded_not_fake_success():
    with patch("app.api.routes.nearby._fetch_overpass_elements", new=AsyncMock(return_value=([], False, True))), \
         patch("app.api.routes.nearby._cache_get", new=AsyncMock(return_value=None)):
        resp = await get_nearby(lat=-37.8136, lng=145.2286, postcode=None, city=None, state=None, facility_type="hospital", radius=None, current_user=_user())
    assert resp["status"] == "degraded"
    assert resp["count"] == 0
    assert resp["results"] == []
    assert resp["error"] == _USER_SAFE_UNAVAILABLE
    assert "TimeoutException" not in str(resp)
    assert "Traceback" not in str(resp)


@pytest.mark.asyncio
async def test_live_success_status_ok_and_caches():
    elements = [{
        "type": "node", "id": 42, "lat": -37.814, "lon": 145.229,
        "tags": {"name": "Live Hospital", "amenity": "hospital"},
    }]
    set_mock = AsyncMock()
    with patch("app.api.routes.nearby._fetch_overpass_elements", new=AsyncMock(return_value=(elements, True, False))), \
         patch("app.api.routes.nearby._cache_set", new=set_mock):
        resp = await get_nearby(lat=-37.8136, lng=145.2286, postcode=None, city=None, state=None, facility_type="hospital", radius=None, current_user=_user())
    assert resp["status"] == "ok"
    assert resp["cached"] is False
    assert resp["count"] >= 1
    assert resp["results"][0]["name"] == "Live Hospital"
    assert set_mock.await_count == 1


@pytest.mark.asyncio
async def test_nominatim_lab_timeout_degraded():
    async def _timeout_get(*args, **kwargs):
        raise httpx.TimeoutException("nom timeout")
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    mock_client.get = AsyncMock(side_effect=_timeout_get)
    with patch("app.api.routes.nearby.httpx.AsyncClient", return_value=mock_client), \
         patch("app.api.routes.nearby._cache_get", new=AsyncMock(return_value=None)):
        resp = await get_nearby(lat=-37.8136, lng=145.2286, postcode=None, city=None, state=None, facility_type="lab", radius=None, current_user=_user())
    assert resp["status"] == "degraded"
    assert resp["results"] == []
    assert resp["error"] == _USER_SAFE_UNAVAILABLE


@pytest.mark.asyncio
async def test_categories_invoke_expected_providers():
    overpass = AsyncMock(return_value=([], True, False))
    labs = AsyncMock(return_value=nearby_mod._ProviderResult(places=[], ok=True, source="nominatim"))
    with patch("app.api.routes.nearby._fetch_overpass_elements", new=overpass), \
         patch("app.api.routes.nearby._search_labs_nominatim", new=labs), \
         patch("app.api.routes.nearby._cache_set", new=AsyncMock()):
        for t in ("hospital", "pharmacy", "gp"):
            await get_nearby(
                lat=-37.8136,
                lng=145.2286,
                postcode=None,
                city=None,
                state=None,
                facility_type=t,
                radius=None,
                current_user=_user(),
            )
        await get_nearby(lat=-37.8136, lng=145.2286, postcode=None, city=None, state=None, facility_type="lab", radius=None, current_user=_user())
    assert overpass.await_count == 3
    assert labs.await_count == 1


@pytest.mark.asyncio
async def test_malformed_overpass_does_not_crash():
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.text = "not-json"
    mock_resp.json.side_effect = ValueError("bad json")
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    mock_client.post = AsyncMock(return_value=mock_resp)
    with patch("app.api.routes.nearby.httpx.AsyncClient", return_value=mock_client), \
         patch("app.api.routes.nearby._cache_get", new=AsyncMock(return_value=None)):
        resp = await get_nearby(lat=-37.8136, lng=145.2286, postcode=None, city=None, state=None, facility_type="pharmacy", radius=None, current_user=_user())
    assert resp["status"] == "degraded"
    assert resp["results"] == []


@pytest.mark.asyncio
async def test_non_au_gps_falls_back_to_default_origin():
    captured = {}
    async def _fake_overpass(query: str):
        captured["query"] = query
        return [], True, False
    with patch("app.api.routes.nearby._fetch_overpass_elements", new=AsyncMock(side_effect=_fake_overpass)), \
         patch("app.api.routes.nearby._cache_set", new=AsyncMock()):
        resp = await get_nearby(lat=37.4, lng=-122.0, postcode=None, city=None, state=None, facility_type="hospital", radius=None, current_user=_user())
    assert resp["location_source"] == "default"
    assert abs(resp["origin"]["lat"] - nearby_mod.DEFAULT_LAT) < 0.01
    assert abs(resp["origin"]["lng"] - nearby_mod.DEFAULT_LNG) < 0.01

