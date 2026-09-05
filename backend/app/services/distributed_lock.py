"""
Redis-backed distributed lock.

Prevents two concurrent search requests for the same medicine from each
triggering a separate (expensive) AI call. Pattern:

    async with DistributedLock(f"medlock:{normalized_query}", ttl=60) as got:
        if got:
            # We own the lock — call AI, write cache.
        else:
            # Someone else is already calling AI. Poll the cache for a few
            # seconds; on hit, return it. On timeout, fall back to AI ourselves
            # (rare — only happens if the lock holder crashes mid-flight).

Implementation details
──────────────────────
- Atomic acquire: SET key value NX EX ttl
- Owner-safe release: Lua compare-and-delete so we never delete someone else's
  lock if our request was slow and the TTL already expired.
- If Redis is unavailable the lock is granted (fail-open). The cost is
  occasional duplicate AI calls during a Redis outage — acceptable.
"""
from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Optional

from app.services.cache_service import _get_redis

logger = logging.getLogger(__name__)

# Lua: only delete if the value still matches our token.
_RELEASE_LUA = """
if redis.call('get', KEYS[1]) == ARGV[1] then
    return redis.call('del', KEYS[1])
else
    return 0
end
"""


class DistributedLock:
    """Async context manager. `__aenter__` returns True if we own the lock."""

    def __init__(self, key: str, *, ttl: int = 60, wait_seconds: float = 0.0):
        """
        key   — Redis key (caller-scoped, e.g. "medlock:panadol")
        ttl   — lock auto-expiry seconds; pick > the worst-case AI latency
        wait_seconds — if > 0, wait up to this long for the lock before giving up.
                       Set to 0 to make `__aenter__` non-blocking.
        """
        self.key   = key
        self.ttl   = ttl
        self.wait  = wait_seconds
        self.token = uuid.uuid4().hex
        self._got  = False

    async def __aenter__(self) -> bool:
        deadline = asyncio.get_event_loop().time() + self.wait
        while True:
            self._got = await self._try_acquire()
            if self._got:
                return True
            if self.wait <= 0 or asyncio.get_event_loop().time() >= deadline:
                return False
            await asyncio.sleep(0.1)

    async def __aexit__(self, exc_type, exc, tb) -> None:
        if not self._got:
            return
        try:
            r = await _get_redis()
            if r is None:
                return                       # Redis went away — let TTL clean up
            await r.eval(_RELEASE_LUA, 1, self.key, self.token)
        except Exception as e:               # never raise out of __aexit__
            logger.debug("lock release error key=%s: %s", self.key, e)

    async def _try_acquire(self) -> bool:
        try:
            r = await _get_redis()
            if r is None:
                # Fail-open: no Redis → pretend we got the lock so the request
                # makes progress. Duplicate AI calls in this window are
                # tolerable; the persistent DB cache eventually dedups them.
                logger.debug("Redis unavailable — granting %s without lock", self.key)
                return True
            # SET key token NX EX ttl  → 'OK' on success, None on contention.
            result = await r.set(self.key, self.token, nx=True, ex=self.ttl)
            return result is not None
        except Exception as e:
            logger.warning("lock acquire error key=%s: %s — granting", self.key, e)
            return True   # fail-open


async def wait_for_value(
    key: str,
    *,
    timeout_seconds: float,
    poll_interval: float = 0.25,
) -> Optional[str]:
    """
    Wait for a Redis key to appear (used by losers of lock contention to pick
    up the winner's freshly-written cache value). Returns the value, or None
    on timeout.
    """
    try:
        r = await _get_redis()
        if r is None:
            return None
        deadline = asyncio.get_event_loop().time() + timeout_seconds
        while asyncio.get_event_loop().time() < deadline:
            v = await r.get(key)
            if v is not None:
                return v
            await asyncio.sleep(poll_interval)
        return None
    except Exception as e:
        logger.debug("wait_for_value error key=%s: %s", key, e)
        return None
