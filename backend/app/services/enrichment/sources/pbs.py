"""
Pharmaceutical Benefits Scheme (PBS) public API source.

    Base URL:      https://data-api.health.gov.au/PBS/api/v3
    Header:        Subscription-Key: <your-key>
    Rate limit:    1 request per 20 seconds, shared across ALL callers
                   that use the same subscription key.
    Cache hint:    PBS schedule updates monthly. 30-day TTL is safe.
    Docs:          https://data.pbs.gov.au/api/api-public.html
                   https://data-api-portal.health.gov.au/api-details

Subscription keys
─────────────────
PBS exposes the public API on Azure APIM, which always requires a
`Subscription-Key` header. There are two ways to get one:

  1. **Shared anonymous key** — the API catalogue publishes this for
     unregistered public use:
         2384af7c667342ceb5a736fe29f1dc6b
     We use it by default so the source works out of the box. Note
     that the 20-second rate limit is shared across EVERYONE in the
     world hitting the API with this same key — which is why we
     globally throttle every call through Redis.

  2. **Your own dedicated key** — free, 5-min registration at
     https://data-api-portal.health.gov.au. A per-tenant key gives you
     your own bucket so noisy neighbours can't starve your nightly
     batch. Set `PBS_SUBSCRIPTION_KEY` in `.env` to override.

How this source behaves
───────────────────────
- Calls the API only after acquiring a global Redis lease
  (`pbs:throttle`, NX-set with 21s TTL). Concurrent workers across
  the fleet serialise through that lock.
- Every successful response is cached in Redis under `pbs:item:<code>`
  for 30 days. Negative results are cached for 24h to avoid hammering
  the rate limit for typos.
- If Redis is unavailable, we fall back to a per-process throttle and
  skip caching. The 20s wait still applies.

NEVER run this on the user-search hot path — the 20s shared limit will
murder your response time. Use it only from the nightly batch enricher.
"""
from __future__ import annotations

import asyncio
import logging
import time

import httpx

from app.services.cache_service import CacheService, _get_redis
from app.services.enrichment.normalizer import (
    extract_dosage_form_and_strength,
    join_list,
)
from app.services.enrichment.sources.base import EnrichmentResult, EnrichmentSource

logger = logging.getLogger(__name__)

# ─── Endpoint ────────────────────────────────────────────────────────────────
_PBS_BASE     = "https://data-api.health.gov.au/PBS/api/v3"
_HTTP_TIMEOUT = 30.0

# Public shared key for unregistered users — published in the PBS API
# catalogue. Subject to the same 20s-per-call limit, shared globally with
# every other unregistered caller. Override per-tenant via .env if you
# have your own key.
_PUBLIC_SHARED_KEY = "2384af7c667342ceb5a736fe29f1dc6b"

# ─── Rate limiting ───────────────────────────────────────────────────────────
_RATE_KEY     = "pbs:throttle"
_RATE_WINDOW  = 21        # seconds; PBS limit is 20, we pad by 1 for jitter
_LOCAL_LOCK   = asyncio.Lock()
_LAST_LOCAL   = 0.0       # monotonic seconds, used when Redis is absent

# ─── Cache TTL ───────────────────────────────────────────────────────────────
_HIT_TTL_SECONDS  = 30 * 24 * 3600
_MISS_TTL_SECONDS = 24 * 3600


# Field name → list of likely keys PBS may emit. Defensive: PBS has
# tweaked field naming across schedule versions.
_FIELD_ALIASES: dict[str, list[str]] = {
    "brand_name":      ["brand_name", "brandName", "trade_name", "item_name"],
    "generic_name":    ["li_drug_name", "drug_name", "active_ingredient",
                        "activeIngredients"],
    "pack_size":       ["pack_quantity", "pack_size", "packSize", "max_quantity"],
    "atc_code":        ["atc_code", "atc"],
    "amt_code":        ["amt_mp", "amt_code", "amt_tpuu", "amt_mpp", "amt_mp_uu"],
    "tga_artg_number": ["artg_number", "artgId", "artg_id"],
    # `li_form` is the canonical form-and-strength field (e.g. "Tablet 333 mg").
    # `schedule_form` is the full schedule line, used as a richer fallback.
    # `manufacturer_code` is NOT a dosage form — it's a 2-letter sponsor
    # abbreviation. Do not put it here.
    "form_strength":   ["li_form", "schedule_form", "form_strength", "form"],
    "pbs_code":        ["pbs_code", "li_item_id"],
}


def _pick(d: dict, names: list[str]):
    for n in names:
        v = d.get(n)
        if v not in (None, "", []):
            return v
    return None


class PbsSource(EnrichmentSource):

    source_name     = "pbs"
    BASE_CONFIDENCE = 0.92

    def __init__(self, subscription_key: str | None = None):
        super().__init__()
        # Caller-supplied key wins; otherwise fall back to the published
        # public anonymous key so the source is usable out of the box.
        self.key = subscription_key or _PUBLIC_SHARED_KEY
        self.using_shared_key = (self.key == _PUBLIC_SHARED_KEY)
        if self.using_shared_key:
            logger.info(
                "[pbs] using shared public anonymous key — set "
                "PBS_SUBSCRIPTION_KEY in .env for a dedicated rate bucket"
            )

    # ── Public entry ────────────────────────────────────────────────────────

    async def fetch(self, *, medicine_id: int, **lookup_keys) -> EnrichmentResult:
        identifier  = lookup_keys.get("pbs_code")
        search_text = (
            lookup_keys.get("brand_name")
            or lookup_keys.get("generic_name")
            or lookup_keys.get("name")
        )
        if not identifier and not search_text:
            return self._none(reason="no_lookup_key")

        # 1) Cache check. Hot rows hit cache and skip the 20s wait entirely.
        cache_key = f"pbs:item:{(identifier or search_text).lower()}"
        cached    = await CacheService.get(cache_key)
        if cached is not None:
            return self._parse_item(cached, cached_hit=True)

        # 2) Distributed throttle.
        await self._await_rate_slot()

        # 3) Live call.
        try:
            item = await self._get(identifier, search_text)
        except httpx.HTTPStatusError as exc:
            if exc.response is not None and exc.response.status_code == 401:
                logger.error("[pbs] 401 — subscription key invalid")
                return self._err(exc)
            return self._err(exc)
        except Exception as exc:
            return self._err(exc)

        if item is None:
            await CacheService.set(cache_key, {"_empty": True}, ttl=_MISS_TTL_SECONDS)
            return self._none(reason="not_found")

        # 4) Cache positive hit for 30 days.
        await CacheService.set(cache_key, item, ttl=_HIT_TTL_SECONDS)
        return self._parse_item(item)

    # ── HTTP ────────────────────────────────────────────────────────────────

    async def _get(self, pbs_code: str | None, search_text: str | None) -> dict | None:
        """
        PBS uses field-specific filter params on /items (drug_name,
        li_drug_name, brand_name, pbs_code). Each call costs one slot in
        the 20-second rate window, so we issue ONE targeted call per
        medicine — the most specific identifier wins. Cache misses on
        names just fall through to the next source (HealthDirect / etc.).
        """
        headers = {
            "Accept":           "application/json",
            "Subscription-Key": self.key,
            "User-Agent":       "AuHealth-AI/1.0",
        }
        params: dict = {"limit": 1}
        if pbs_code:
            params["pbs_code"] = pbs_code
        elif search_text:
            # `drug_name` is the canonical generic-name field. It accepts
            # partial matches and is the most permissive single field.
            params["drug_name"] = search_text
        else:
            return None

        async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT, headers=headers) as client:
            resp = await client.get(f"{_PBS_BASE}/items", params=params)

        if resp.status_code == 404:
            return None
        if resp.status_code == 429:
            logger.warning("[pbs] 429 — backing off %ss", _RATE_WINDOW)
            await asyncio.sleep(_RATE_WINDOW)
            return None
        resp.raise_for_status()

        body = resp.json() or {}
        data = body.get("data") or []
        if isinstance(data, dict):
            return data
        return data[0] if data else None

        if resp.status_code == 404:
            return None
        if resp.status_code == 429:
            logger.warning("[pbs] 429 — backing off %ss", _RATE_WINDOW)
            await asyncio.sleep(_RATE_WINDOW)
            return None
        resp.raise_for_status()

        body = resp.json() or {}
        if isinstance(body, dict):
            items = body.get("data") or body.get("items") or []
            if isinstance(items, dict):
                items = [items]
        else:
            items = body if isinstance(body, list) else []
        return items[0] if items else None

    # ── Distributed rate limiting ───────────────────────────────────────────

    async def _await_rate_slot(self) -> None:
        global _LAST_LOCAL
        r = await _get_redis()
        if r is None:
            async with _LOCAL_LOCK:
                wait = _RATE_WINDOW - (time.monotonic() - _LAST_LOCAL)
                if wait > 0:
                    logger.info("[pbs] local throttle: sleeping %.1fs", wait)
                    await asyncio.sleep(wait)
                _LAST_LOCAL = time.monotonic()
            return

        # SETNX with EX gives us a global lease that auto-expires.
        while True:
            got = await r.set(_RATE_KEY, "1", nx=True, ex=_RATE_WINDOW)
            if got:
                return
            ttl = await r.ttl(_RATE_KEY)
            if ttl is None or ttl < 0:
                continue
            sleep_for = min(max(ttl, 1), _RATE_WINDOW)
            logger.info("[pbs] global throttle: sleeping %ss", sleep_for)
            await asyncio.sleep(sleep_for)

    # ── Parsing ─────────────────────────────────────────────────────────────

    def _parse_item(self, item: dict, *, cached_hit: bool = False) -> EnrichmentResult:
        if item.get("_empty"):
            return self._none(reason="cached_empty")

        brand   = _pick(item, _FIELD_ALIASES["brand_name"])
        generic = _pick(item, _FIELD_ALIASES["generic_name"])
        if isinstance(generic, list):
            generic = join_list(generic)

        raw_form_strength = _pick(item, _FIELD_ALIASES["form_strength"])
        form, strength = (extract_dosage_form_and_strength(raw_form_strength)
                          if raw_form_strength else (None, None))

        pack     = _pick(item, _FIELD_ALIASES["pack_size"])
        atc      = _pick(item, _FIELD_ALIASES["atc_code"])
        amt      = _pick(item, _FIELD_ALIASES["amt_code"])
        artg     = _pick(item, _FIELD_ALIASES["tga_artg_number"])
        pbs_code = _pick(item, _FIELD_ALIASES["pbs_code"])

        fields: dict = {}
        if brand:    fields["brand_name"]        = brand
        if generic:
            fields["generic_name"]      = generic
            fields["active_ingredient"] = generic
        if form:     fields["dosage_form"]       = form
        if strength: fields["strength"]          = strength
        if pack:     fields["pack_size"]         = str(pack)
        if atc:
            fields["atc_code"]          = atc
            fields["therapeutic_class"] = self._atc_to_class(atc)
        if amt:      fields["amt_code"]          = str(amt)
        if pbs_code: fields["pbs_code"]          = str(pbs_code)
        if artg:
            fields["tga_artg_number"] = str(artg)
            fields["tga_registered"]  = True

        confs = {f: self.BASE_CONFIDENCE for f in fields}
        if "pbs_code" in fields:        confs["pbs_code"]        = 0.98
        if "tga_artg_number" in fields: confs["tga_artg_number"] = 0.95

        return self._ok(
            fields=fields,
            field_confidence=confs,
            evidence={
                "pbs_code": pbs_code,
                "cached":   cached_hit,
                "url":      f"{_PBS_BASE}/items?pbs_code={pbs_code or ''}",
            },
        )

    # ── ATC code → therapeutic class lookup ─────────────────────────────────
    _ATC_PREFIX_CLASS = {
        "A": "Alimentary tract and metabolism",
        "B": "Blood and blood-forming organs",
        "C": "Cardiovascular",
        "D": "Dermatologicals",
        "G": "Genito-urinary system / sex hormones",
        "H": "Systemic hormonal preparations",
        "J": "Anti-infectives for systemic use",
        "L": "Antineoplastic and immunomodulating agents",
        "M": "Musculo-skeletal",
        "N": "Nervous system",
        "P": "Antiparasitic",
        "R": "Respiratory",
        "S": "Sensory organs",
        "V": "Various",
    }

    @classmethod
    def _atc_to_class(cls, atc_code: str) -> str | None:
        if not atc_code:
            return None
        return cls._ATC_PREFIX_CLASS.get(atc_code[0].upper())
