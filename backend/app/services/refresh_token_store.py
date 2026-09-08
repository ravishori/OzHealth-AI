"""
HN-AUTH-011 — per-refresh-token rotation store (rotate-on-use).

Stores only opaque refresh JWT ``jti`` → user_id bindings (no raw tokens, no PHI).

Backend preference:
  1. Existing Redis client from ``cache_service._get_redis`` (shared config).
  2. Process-local fallback when Redis is unavailable (single-process / tests).

Security semantics:
  * Unknown / already-consumed ``jti`` → reject (fail closed).
  * Consume is atomic (one winner under concurrent refresh of the same token).
  * Does NOT bump global ``users.token_version`` (multi-device safe).
"""
from __future__ import annotations

import asyncio
import logging
import time
from typing import Dict, Optional, Tuple

from app.services.cache_service import _get_redis

logger = logging.getLogger(__name__)

_KEY_PREFIX = "auth:refresh:jti:"

# Process-local fallback: jti → (user_id, expires_at_epoch)
_memory: Dict[str, Tuple[int, float]] = {}
_memory_lock = asyncio.Lock()

# Lua: delete key only if value equals expected user_id (atomic consume).
_CONSUME_LUA = """
local v = redis.call('GET', KEYS[1])
if not v then
  return 0
end
if v ~= ARGV[1] then
  return 0
end
redis.call('DEL', KEYS[1])
return 1
"""


def _key(jti: str) -> str:
    return f"{_KEY_PREFIX}{jti}"


def _reset_memory_store_for_tests() -> None:
    """Test helper — clear in-process bindings between cases."""
    _memory.clear()


class RefreshTokenStore:
    """Active refresh-token jti registry with atomic rotate-on-use consume."""

    @staticmethod
    async def register(jti: str, user_id: int, ttl_seconds: int) -> bool:
        """
        Register an active refresh jti for ``user_id``.

        Returns True when the binding was persisted (Redis or memory).
        Never stores the raw JWT — only the opaque jti and user id.
        """
        if not jti or user_id is None or ttl_seconds <= 0:
            return False

        key = _key(jti)
        uid = str(int(user_id))

        try:
            r = await _get_redis()
            if r is not None:
                await r.setex(key, int(ttl_seconds), uid)
                return True
        except Exception as exc:
            logger.warning("Refresh jti Redis register failed — using memory fallback")
            logger.debug("refresh register error: %s", type(exc).__name__)

        async with _memory_lock:
            _memory[jti] = (int(user_id), time.time() + float(ttl_seconds))
        return True

    @staticmethod
    async def consume(jti: str, user_id: int) -> bool:
        """
        Atomically consume ``jti`` if it is bound to ``user_id``.

        Returns True only for the first successful consumer. Concurrent callers
        with the same jti: at most one receives True.
        """
        if not jti or user_id is None:
            return False

        key = _key(jti)
        uid = str(int(user_id))

        try:
            r = await _get_redis()
            if r is not None:
                result = await r.eval(_CONSUME_LUA, 1, key, uid)
                return int(result or 0) == 1
        except Exception as exc:
            logger.warning("Refresh jti Redis consume failed — trying memory fallback")
            logger.debug("refresh consume error: %s", type(exc).__name__)

        async with _memory_lock:
            entry: Optional[Tuple[int, float]] = _memory.get(jti)
            if entry is None:
                return False
            bound_uid, expires_at = entry
            if time.time() > expires_at:
                _memory.pop(jti, None)
                return False
            if int(bound_uid) != int(user_id):
                # Do not destroy another principal's binding on mismatch.
                return False
            _memory.pop(jti, None)
            return True

    @staticmethod
    async def is_active(jti: str, user_id: int) -> bool:
        """Non-destructive check (tests / diagnostics). Fail closed on errors."""
        if not jti or user_id is None:
            return False
        key = _key(jti)
        uid = str(int(user_id))
        try:
            r = await _get_redis()
            if r is not None:
                val = await r.get(key)
                return val == uid
        except Exception:
            pass
        async with _memory_lock:
            entry = _memory.get(jti)
            if entry is None:
                return False
            bound_uid, expires_at = entry
            if time.time() > expires_at:
                return False
            return int(bound_uid) == int(user_id)
