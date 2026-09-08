"""
HN-AI-009 — fail-closed per-user AI product quota.

Controls aggregate authenticated AI Health Assistant usage over a configured
window (default: 40 requests / 24h — implementation default, overridable via
settings/env). Does NOT use CacheService.increment_counter (fail-open).

Security:
  * Quota owner = authenticated ``user_id`` only (never client-supplied ids).
  * Redis unavailable / script failure → deny (fail closed).
  * Atomic INCR+limit check via Lua (concurrent-safe).
  * Keys store only opaque counters — no PHI/prompts/responses.
  * Consume-before-provider: quota is charged when admission is granted,
    even if the later AI provider call fails (cost/abuse control).
"""
from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from typing import Dict, Optional, Tuple

from app.core.config import settings
from app.core.exceptions import RateLimitError
from app.services.cache_service import _get_redis

logger = logging.getLogger(__name__)

_KEY_PREFIX = "ai:quota:user:"

# Atomic admit: INCR; set TTL on first hit; if over limit, DECR and deny.
_ADMIT_LUA = """
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local ttl = tonumber(ARGV[2])
local count = redis.call('INCR', key)
if count == 1 then
  redis.call('EXPIRE', key, ttl)
end
if count > limit then
  redis.call('DECR', key)
  local remain_ttl = redis.call('TTL', key)
  if remain_ttl < 0 then
    remain_ttl = ttl
  end
  return {0, remain_ttl, limit, 0}
end
local remain_ttl = redis.call('TTL', key)
if remain_ttl < 0 then
  remain_ttl = ttl
end
local remaining = limit - count
if remaining < 0 then
  remaining = 0
end
return {1, remain_ttl, limit, remaining}
"""

# Optional in-process backend for unit tests only (injected explicitly).
_test_backend: Optional["_MemoryQuotaBackend"] = None


@dataclass(frozen=True)
class AiQuotaDecision:
    allowed: bool
    limit: int
    remaining: int
    retry_after: int


class _MemoryQuotaBackend:
    """Deterministic in-memory admit used only when tests inject it."""

    def __init__(self) -> None:
        self._data: Dict[str, Tuple[int, float]] = {}
        self._lock = asyncio.Lock()

    def reset(self) -> None:
        self._data.clear()

    async def admit(self, key: str, limit: int, ttl: int) -> AiQuotaDecision:
        async with self._lock:
            now = time.time()
            count, expires_at = self._data.get(key, (0, now + ttl))
            if now >= expires_at:
                count, expires_at = 0, now + ttl
            if count >= limit:
                retry = max(1, int(expires_at - now))
                return AiQuotaDecision(False, limit, 0, retry)
            count += 1
            self._data[key] = (count, expires_at)
            retry = max(1, int(expires_at - now))
            return AiQuotaDecision(True, limit, max(0, limit - count), retry)


def use_memory_backend_for_tests() -> _MemoryQuotaBackend:
    """Test helper — install fail-closed in-memory backend (not for production)."""
    global _test_backend
    backend = _MemoryQuotaBackend()
    _test_backend = backend
    return backend


def reset_quota_backend_for_tests() -> None:
    """Test helper — restore Redis-only production path."""
    global _test_backend
    if _test_backend is not None:
        _test_backend.reset()
    _test_backend = None


def _quota_key(user_id: int) -> str:
    return f"{_KEY_PREFIX}{int(user_id)}"


class AiQuotaService:
    """Per-authenticated-user AI quota enforcement (HN-AI-009)."""

    @staticmethod
    async def enforce(user_id: int) -> AiQuotaDecision:
        """
        Atomically consume one AI quota unit for ``user_id``.

        Raises RateLimitError when denied or when quota state cannot be
        determined (fail closed). Never logs prompts/PHI.
        """
        if user_id is None:
            raise RateLimitError(
                "AI request limit unavailable. Please try again later.",
                retry_after=60,
            )

        limit = int(getattr(settings, "AI_QUOTA_LIMIT", 40) or 40)
        ttl = int(getattr(settings, "AI_QUOTA_WINDOW_SECONDS", 86400) or 86400)
        if limit < 1 or ttl < 1:
            raise RateLimitError(
                "AI request limit unavailable. Please try again later.",
                retry_after=60,
            )

        key = _quota_key(user_id)

        if _test_backend is not None:
            decision = await _test_backend.admit(key, limit, ttl)
            if not decision.allowed:
                raise RateLimitError(
                    "AI request limit reached. Please try again later.",
                    retry_after=decision.retry_after,
                )
            return decision

        try:
            r = await _get_redis()
        except Exception:
            r = None

        if r is None:
            logger.warning("AI quota fail-closed: Redis unavailable")
            raise RateLimitError(
                "AI request limit unavailable. Please try again later.",
                retry_after=60,
            )

        try:
            result = await r.eval(_ADMIT_LUA, 1, key, str(limit), str(ttl))
            allowed = int(result[0]) == 1
            retry_after = max(1, int(result[1] or ttl))
            remaining = max(0, int(result[3] or 0))
            decision = AiQuotaDecision(allowed, limit, remaining, retry_after)
        except Exception as exc:
            logger.warning(
                "AI quota fail-closed: Redis evaluate error (%s)",
                type(exc).__name__,
            )
            raise RateLimitError(
                "AI request limit unavailable. Please try again later.",
                retry_after=60,
            ) from None

        if not decision.allowed:
            raise RateLimitError(
                "AI request limit reached. Please try again later.",
                retry_after=decision.retry_after,
            )
        return decision
