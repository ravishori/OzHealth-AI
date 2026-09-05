"""
Nightly cache refresh worker.

APScheduler runs `refresh_top_medicines` once per day at 02:30 Australia/Sydney
(off-peak). It re-enriches the top-N cache entries whose `cache_expiry` is
within the next 24 hours, so traffic during the morning rush never sees a
cold cache for popular drugs.

The worker:
  - Runs serially (max_instances=1) so two overlapping nightly runs never
    fight for the same DistributedLock.
  - Reads its work list via MedicineCacheRepository.list_for_refresh — set-
    based, indexed.
  - Calls MedicineSearchService.refresh per entry, which acquires the same
    Redis lock as live requests. If a user happens to search the same medicine
    during the refresh, one waits for the other; no duplicate AI calls.
"""
from __future__ import annotations

import logging
from typing import Optional

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.core.database import AsyncSessionLocal
from app.repositories.medicine_cache_repository import MedicineCacheRepository
from app.services.medicine_search_service import MedicineSearchService

logger = logging.getLogger(__name__)

# Cap per nightly run — keeps wall time bounded and AI spend predictable.
_NIGHTLY_REFRESH_LIMIT = 200

_scheduler: Optional[AsyncIOScheduler] = None


# ─── Job ────────────────────────────────────────────────────────────────────
async def refresh_top_medicines(limit: int = _NIGHTLY_REFRESH_LIMIT) -> int:
    """Refresh the top `limit` cache entries due for renewal. Returns count."""
    refreshed = 0
    async with AsyncSessionLocal() as session:
        rows = await MedicineCacheRepository(session).list_for_refresh(limit=limit)
        await session.commit()           # release the read connection
    logger.info("[cache-worker] picked %d entries to refresh", len(rows))

    for row in rows:
        try:
            async with AsyncSessionLocal() as session:
                svc = MedicineSearchService(session)
                # Use the original query_text so the prompt looks identical
                # to what created the entry — same prompt = same cache key.
                result = await svc.refresh(row.query_text, force=True)
                await session.commit()
                if result.get("refreshed"):
                    refreshed += 1
        except Exception:
            logger.exception("[cache-worker] refresh failed for %s", row.normalized_query)

    logger.info("[cache-worker] refreshed %d/%d entries", refreshed, len(rows))
    return refreshed


# ─── Lifecycle ──────────────────────────────────────────────────────────────
def start_scheduler() -> AsyncIOScheduler:
    """Idempotent. Safe to call once at app startup."""
    global _scheduler
    if _scheduler is not None:
        return _scheduler

    _scheduler = AsyncIOScheduler(timezone="Australia/Sydney")
    _scheduler.add_job(
        refresh_top_medicines,
        CronTrigger(hour=2, minute=30),     # 02:30 AEDT/AEST
        id              = "medicine_cache_nightly_refresh",
        name            = "Medicine cache nightly refresh (02:30 AEDT)",
        max_instances   = 1,                # never overlap with itself
        coalesce        = True,             # if missed, run once when next due
        replace_existing= True,
    )
    _scheduler.start()
    logger.info("Medicine cache refresh scheduler started (daily 02:30 AEDT)")
    return _scheduler


def stop_scheduler() -> None:
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
        logger.info("Medicine cache refresh scheduler stopped")
