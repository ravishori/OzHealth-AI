"""
Redis cache service for HealthNest.

Provides async get/set/delete/invalidate_prefix helpers.
Falls back to no-op (always miss) when Redis is unavailable so the app
continues to work without caching in environments without Redis.

TTL constants (seconds):
    MEDICINE_SEARCH  = 3600   (1 hour)
    MEDICINE_DETAIL  = 21600  (6 hours)
    USER_PROFILE     = 300    (5 minutes)
    HEALTH_SUMMARY   = 1800   (30 minutes)
    NEARBY_SERVICES  = 900    (15 minutes)
"""
import json
import logging
from typing import Any, Optional

logger = logging.getLogger(__name__)

# â”€â”€â”€ TTL constants â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
MEDICINE_SEARCH_TTL = 3600
MEDICINE_DETAIL_TTL = 21600
USER_PROFILE_TTL = 300
HEALTH_SUMMARY_TTL = 1800
NEARBY_TTL = 900

# â”€â”€â”€ Redis client (lazy init with backoff) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
_redis = None
_redis_next_retry: float = 0.0   # epoch seconds â€” don't retry before this time


async def _get_redis():
    """
    Return a live Redis client, or None if Redis is unavailable.

    After the first failure we wait 30 seconds before retrying so that a
    missing Redis instance doesn't add a 3-second socket-connect delay to
    every single HTTP request.
    """
    import time
    global _redis, _redis_next_retry

    # Return cached working client immediately
    if _redis is not None:
        return _redis

    # Still in back-off window after a previous failure
    if time.monotonic() < _redis_next_retry:
        return None

    try:
        from redis.asyncio import from_url
        from app.core.config import settings
        _redis = from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
            socket_connect_timeout=3,   # give up connecting after 3 s
            socket_timeout=3,           # give up on read/write after 3 s
        )
        await _redis.ping()
        logger.info("Redis connected: %s", settings.REDIS_URL)
    except Exception as exc:
        logger.warning("Redis unavailable â€” caching disabled (retry in 30 s): %s", exc)
        _redis = None
        _redis_next_retry = time.monotonic() + 30   # back off 30 seconds
    return _redis


class CacheService:

    @staticmethod
    async def get(key: str) -> Optional[Any]:
        """Return parsed JSON value or None on miss/error."""
        try:
            r = await _get_redis()
            if r is None:
                return None
            raw = await r.get(key)
            if raw is None:
                return None
            return json.loads(raw)
        except Exception as exc:
            logger.debug("Cache GET error for key %s: %s", key, exc)
            return None

    @staticmethod
    async def set(key: str, value: Any, ttl: int = 300) -> bool:
        """Serialize value to JSON and store with TTL. Returns True on success."""
        try:
            r = await _get_redis()
            if r is None:
                return False
            await r.setex(key, ttl, json.dumps(value, default=str))
            return True
        except Exception as exc:
            logger.debug("Cache SET error for key %s: %s", key, exc)
            return False

    @staticmethod
    async def delete(key: str) -> bool:
        """Delete a single key."""
        try:
            r = await _get_redis()
            if r is None:
                return False
            await r.delete(key)
            return True
        except Exception as exc:
            logger.debug("Cache DELETE error for key %s: %s", key, exc)
            return False

    @staticmethod
    async def invalidate_prefix(prefix: str) -> int:
        """Delete all keys matching prefix:*. Returns number of keys deleted."""
        try:
            r = await _get_redis()
            if r is None:
                return 0
            keys = await r.keys(f"{prefix}:*")
            if keys:
                await r.delete(*keys)
            return len(keys)
        except Exception as exc:
            logger.debug("Cache INVALIDATE error for prefix %s: %s", prefix, exc)
            return 0

    # â”€â”€ Rate limiting helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @staticmethod
    async def increment_counter(key: str, ttl: int = 900) -> int:
        """
        Increment a counter key (creating it if missing) with TTL.
        Returns the new count. Used for rate limiting.
        """
        try:
            r = await _get_redis()
            if r is None:
                return 0  # no Redis â†’ no rate limiting (fail open)
            count = await r.incr(key)
            if count == 1:
                await r.expire(key, ttl)
            return count
        except Exception as exc:
            logger.debug("Cache INCR error for key %s: %s", key, exc)
            return 0

    @staticmethod
    async def get_ttl(key: str) -> int:
        """Return remaining TTL in seconds, or -1 if key doesn't exist."""
        try:
            r = await _get_redis()
            if r is None:
                return -1
            return await r.ttl(key)
        except Exception:
            return -1
