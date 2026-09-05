"""
End-to-end search orchestrator.

This is the only service the route handler talks to. It coordinates:
  1. Normalisation.
  2. Persistent cache lookup.
  3. DB lookup.
  4. Distributed-lock-protected AI enrichment.
  5. Cache write.
  6. Counter updates on `medicines`.

Hot path (cache hit):
    normalize → 1 SELECT → 1 UPDATE → return.

Cold path (full miss):
    normalize → cache miss → DB miss → acquire lock → AI call →
    cache UPSERT → return.
"""
from __future__ import annotations

import logging
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medicine import Medicine
from app.repositories.medicine_repository import MedicineRepository
from app.services.distributed_lock import DistributedLock
from app.services.medicine_cache_service import MedicineCacheService
from app.services.medicine_enrichment_service import (
    CURRENT_PROMPT_VERSION,
    enrichment_service,
)
from app.utils.medicine_normalizer import is_meaningful, normalize_query

logger = logging.getLogger(__name__)

# Lock TTL must exceed worst-case AI latency. Anthropic Haiku for our prompt
# typically returns in 2–6s; 30s gives generous headroom.
_LOCK_TTL_SECONDS    = 30
# Losers of lock contention wait this long for the winner's cache write.
_LOCK_WAIT_SECONDS   = 8.0


class MedicineSearchService:

    def __init__(self, db: AsyncSession):
        self.db        = db
        self.med_repo  = MedicineRepository(db)
        self.cache     = MedicineCacheService(db)

    # ── Public ───────────────────────────────────────────────────────────────

    async def search(self, query: str) -> dict[str, Any]:
        """Return the standard response envelope (see schemas.medicine_cache)."""
        normalized = normalize_query(query)
        if not is_meaningful(normalized):
            return self._envelope(
                source="invalid",
                normalized=normalized,
                ai_response={"error": "query too short after normalisation"},
            )

        # 1) Try the persistent cache.
        cache_row = await self.cache.get_valid(normalized)
        if cache_row is not None:
            await self.cache.record_hit(cache_row.cache_id)
            if cache_row.medicine_id:
                await self.med_repo.record_search(cache_row.medicine_id, cache_hit=True)
            return self._envelope(
                source="cache",
                cache_hit=True,
                normalized=normalized,
                medicine_id=cache_row.medicine_id,
                ai_response=cache_row.ai_response or {},
                prompt_version=cache_row.prompt_version,
                cached_at=cache_row.created_at,
                cache_expires=cache_row.cache_expiry,
            )

        # 2) Cache miss. Find an existing medicine record.
        medicine = await self.med_repo.find_by_normalized(normalized)

        # 3) Serialise concurrent AI calls for the same query via Redis lock.
        lock_key = f"medlock:{normalized}"
        async with DistributedLock(
            lock_key, ttl=_LOCK_TTL_SECONDS, wait_seconds=_LOCK_WAIT_SECONDS
        ) as got_lock:
            if not got_lock:
                # Someone else owns the lock. Re-check the cache — they may
                # have just written it.
                cache_row = await self.cache.get_valid(normalized)
                if cache_row is not None:
                    await self.cache.record_hit(cache_row.cache_id)
                    return self._envelope(
                        source         = "cache",
                        cache_hit      = True,
                        normalized     = normalized,
                        medicine_id    = cache_row.medicine_id,
                        ai_response    = cache_row.ai_response or {},
                        prompt_version = cache_row.prompt_version,
                        cached_at      = cache_row.created_at,
                        cache_expires  = cache_row.cache_expiry,
                    )
                # Still nothing. Continue without the lock — the duplicate AI
                # call is the cost of safety.
                logger.warning("[search] lock timeout for %s — calling AI anyway", normalized)

            # 4) Resolve the AI payload.
            if medicine is not None:
                ai_response = await enrichment_service.enrich_known_medicine(medicine)
                source = "ai+db"
            else:
                ai_response = await enrichment_service.enrich_unknown_query(query)
                source = "ai"

            # 5) Persist to cache (idempotent UPSERT).
            await self.cache.save(
                normalized      = normalized,
                query_text      = query,
                medicine        = medicine,
                ai_response     = ai_response,
                prompt_version  = CURRENT_PROMPT_VERSION,
                source_type     = source,
            )

            # 6) Counter bookkeeping on the medicine row.
            if medicine is not None:
                await self.med_repo.record_search(medicine.id, cache_hit=False)
                await self.med_repo.record_ai_hit(medicine.id)
                await self.med_repo.save_enrichment(
                    medicine.id,
                    side_effects        = ai_response.get("side_effect_summary"),
                    warnings            = ai_response.get("warning_summary"),
                    cache_version       = CURRENT_PROMPT_VERSION,
                )

            return self._envelope(
                source         = source,
                cache_hit      = False,
                ai_call_made   = True,
                normalized     = normalized,
                medicine_id    = medicine.id if medicine else None,
                medicine_name  = medicine.name if medicine else None,
                generic_name   = medicine.generic_name if medicine else None,
                ai_response    = ai_response,
                prompt_version = CURRENT_PROMPT_VERSION,
            )

    async def refresh(self, query: str, *, force: bool = False) -> dict[str, Any]:
        """
        Force a cache refresh for a specific query. Used by ops + the nightly
        worker. Acquires the lock so we don't fight a live request.
        """
        normalized = normalize_query(query)
        if not is_meaningful(normalized):
            return {"refreshed": False, "detail": "query too short", "normalized_query": normalized}

        # Mark for refresh first so any concurrent reader knows the row is stale.
        if not force:
            await self.cache.mark_needs_refresh(normalized)

        lock_key = f"medlock:{normalized}"
        async with DistributedLock(lock_key, ttl=_LOCK_TTL_SECONDS, wait_seconds=2.0) as got:
            if not got:
                return {"refreshed": False, "detail": "lock held by another worker",
                        "normalized_query": normalized}

            medicine = await self.med_repo.find_by_normalized(normalized)
            ai_response = (
                await enrichment_service.enrich_known_medicine(medicine)
                if medicine else
                await enrichment_service.enrich_unknown_query(query)
            )
            row = await self.cache.save(
                normalized      = normalized,
                query_text      = query,
                medicine        = medicine,
                ai_response     = ai_response,
                prompt_version  = CURRENT_PROMPT_VERSION,
                source_type     = "refresh",
            )
            return {
                "refreshed":        True,
                "normalized_query": normalized,
                "new_expiry":       row.cache_expiry,
            }

    # ── Helpers ──────────────────────────────────────────────────────────────

    @staticmethod
    def _envelope(
        *,
        source: str,
        normalized: str,
        ai_response: dict,
        cache_hit: bool = False,
        ai_call_made: bool = False,
        medicine_id: int | None = None,
        medicine_name: str | None = None,
        generic_name: str | None = None,
        prompt_version: str | None = None,
        cached_at = None,
        cache_expires = None,
    ) -> dict[str, Any]:
        return {
            "medicine_id":      medicine_id,
            "name":             medicine_name,
            "generic_name":     generic_name,
            "ai_response":      ai_response,
            "source":           source,
            "cache_hit":        cache_hit,
            "ai_call_made":     ai_call_made,
            "normalized_query": normalized,
            "prompt_version":   prompt_version,
            "cached_at":        cached_at,
            "cache_expires":    cache_expires,
        }
