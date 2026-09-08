"""HN-AI-009 — per-user AI rate limiting / quotas (AI009-BE-01..10)."""
from __future__ import annotations

import asyncio
import inspect
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import ai_assistant as ai_route
from app.core.config import settings
from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.exceptions import RateLimitError
from app.core.security import create_access_token
from app.services import ai_quota_service as quota_mod
from app.services.ai_quota_service import (
    AiQuotaService,
    reset_quota_backend_for_tests,
    use_memory_backend_for_tests,
)


def _user(uid: int = 1, name: str = "Alice"):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@example.com",
        name=name,
        age=30,
        gender="female",
        blood_group="O+",
        health_conditions="[]",
        allergies="[]",
        is_active=True,
        token_version=0,
    )


@pytest.fixture(autouse=True)
def _quota_test_env(monkeypatch):
    monkeypatch.setattr(settings, "AI_QUOTA_LIMIT", 3)
    monkeypatch.setattr(settings, "AI_QUOTA_WINDOW_SECONDS", 3600)
    backend = use_memory_backend_for_tests()
    yield backend
    reset_quota_backend_for_tests()


def _ai_app(user):
    app = FastAPI()
    app.include_router(ai_route.router, prefix="/api/v1/ai")

    from app.core.exceptions import AppException
    from fastapi.responses import JSONResponse

    @app.exception_handler(AppException)
    async def _app_exc(_request, exc: AppException):
        headers = {}
        if isinstance(exc, RateLimitError):
            headers["Retry-After"] = str(exc.retry_after)
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": exc.error_code, "message": exc.message},
            headers=headers,
        )

    async def _override_user():
        return user

    async def _override_db():
        db = AsyncMock()
        result = MagicMock()
        result.scalar_one_or_none.return_value = None
        result.scalars.return_value.all.return_value = []
        db.execute = AsyncMock(return_value=result)
        db.commit = AsyncMock()

        async def _refresh(obj):
            if getattr(obj, "id", None) is None:
                obj.id = 101

        db.refresh = AsyncMock(side_effect=_refresh)
        db.add = MagicMock()
        yield db

    app.dependency_overrides[get_current_user] = _override_user
    app.dependency_overrides[get_db] = _override_db
    return app


@pytest.mark.anyio
async def test_ai009_be_01_allowed_request_passes():
    """AI009-BE-01: allowed AI request passes quota enforcement."""
    decision = await AiQuotaService.enforce(1)
    assert decision.allowed is True
    assert decision.remaining == 2


@pytest.mark.anyio
async def test_ai009_be_02_quota_tied_to_authenticated_user():
    """AI009-BE-02: quota key is authenticated user identity."""
    assert quota_mod._quota_key(42) == "ai:quota:user:42"
    await AiQuotaService.enforce(7)
    # Second user still has full independent budget
    d = await AiQuotaService.enforce(8)
    assert d.allowed is True
    assert d.remaining == 2


@pytest.mark.anyio
async def test_ai009_be_03_exhaustion_blocks():
    """AI009-BE-03: quota exhaustion blocks additional AI requests."""
    for _ in range(3):
        await AiQuotaService.enforce(1)
    with pytest.raises(RateLimitError) as ei:
        await AiQuotaService.enforce(1)
    assert ei.value.status_code == 429
    assert "limit reached" in ei.value.message.lower()


@pytest.mark.anyio
async def test_ai009_be_04_reset_ttl_behavior():
    """AI009-BE-04: after window expiry, quota resets."""
    backend = use_memory_backend_for_tests()
    key = quota_mod._quota_key(1)
    # Force near-expiry state then expire
    backend._data[key] = (3, 0)  # already expired
    d = await AiQuotaService.enforce(1)
    assert d.allowed is True
    assert d.remaining == 2


@pytest.mark.anyio
async def test_ai009_be_05_user_isolation():
    """AI009-BE-05: User A cannot consume User B's quota."""
    for _ in range(3):
        await AiQuotaService.enforce(1)
    with pytest.raises(RateLimitError):
        await AiQuotaService.enforce(1)
    # User B still allowed
    d = await AiQuotaService.enforce(2)
    assert d.allowed is True


@pytest.mark.anyio
async def test_ai009_be_06_client_user_id_cannot_bypass(monkeypatch):
    """AI009-BE-06: client-supplied user identity cannot override JWT principal."""
    user = _user(1)
    app = _ai_app(user)
    calls = {"n": 0}

    async def _fake_chat(*args, **kwargs):
        calls["n"] += 1
        return "Safe lifestyle tip — consult a clinician for personal advice."

    monkeypatch.setattr(ai_route, "chat_with_health_assistant", _fake_chat)
    monkeypatch.setattr(ai_route, "_ai_available", lambda: False)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Exhaust user 1
        for _ in range(3):
            resp = await client.post(
                "/api/v1/ai/chat",
                json={"message": "hello", "user_id": 999, "family_member_id": 5},
            )
            assert resp.status_code == 200
        blocked = await client.post(
            "/api/v1/ai/chat",
            json={"message": "again", "user_id": 999},
        )
    assert blocked.status_code == 429
    assert calls["n"] == 3  # denied request never called provider


@pytest.mark.anyio
async def test_ai009_be_07_redis_unavailable_fail_closed(monkeypatch):
    """AI009-BE-07: Redis unavailable fails closed."""
    reset_quota_backend_for_tests()  # force Redis path

    async def _no_redis():
        return None

    monkeypatch.setattr(quota_mod, "_get_redis", _no_redis)
    with pytest.raises(RateLimitError) as ei:
        await AiQuotaService.enforce(1)
    assert "unavailable" in ei.value.message.lower()
    assert "redis" not in ei.value.message.lower()


@pytest.mark.anyio
async def test_ai009_be_08_concurrent_limit_enforcement():
    """AI009-BE-08: concurrent requests cannot exceed configured limit."""
    results = await asyncio.gather(
        *[asyncio.create_task(_admit_soft(1)) for _ in range(10)],
        return_exceptions=False,
    )
    allowed = sum(1 for r in results if r is True)
    denied = sum(1 for r in results if r is False)
    assert allowed == 3
    assert denied == 7


async def _admit_soft(uid: int) -> bool:
    try:
        await AiQuotaService.enforce(uid)
        return True
    except RateLimitError:
        return False


@pytest.mark.anyio
async def test_ai009_be_09_safety_path_still_invoked(monkeypatch):
    """AI009-BE-09: existing AI safety path still executes when quota allows."""
    user = _user(1)
    app = _ai_app(user)
    seen = {"safety": False}

    async def _fake_chat(messages, user_context=None, system_override=None):
        # Simulate HN-AI-010 path still being the service entry used by route
        src = inspect.getsource(ai_route.chat)
        assert "chat_with_health_assistant" in src
        seen["safety"] = True
        return (
            "General wellness information only — not a diagnosis. "
            "Seek professional care for personal medical decisions."
        )

    monkeypatch.setattr(ai_route, "chat_with_health_assistant", _fake_chat)
    monkeypatch.setattr(ai_route, "_ai_available", lambda: True)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/api/v1/ai/chat", json={"message": "sleep tips"})
    assert resp.status_code == 200
    assert seen["safety"] is True
    assert "diagnosis" in resp.json()["reply"].lower() or "professional" in resp.json()["reply"].lower()


@pytest.mark.anyio
async def test_ai009_be_10_guidance_and_provider_not_called_when_denied(monkeypatch):
    """AI009-BE-10: health-guidance shares quota; denied → provider not called."""
    user = _user(1)
    app = _ai_app(user)
    calls = {"n": 0}

    async def _fake_chat(*args, **kwargs):
        calls["n"] += 1
        return "Guidance placeholder"

    monkeypatch.setattr(ai_route, "chat_with_health_assistant", _fake_chat)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for _ in range(3):
            ok = await client.post(
                "/api/v1/ai/health-guidance",
                json={"topic": "sleep"},
            )
            assert ok.status_code == 200
        denied = await client.post(
            "/api/v1/ai/health-guidance",
            json={"topic": "sleep"},
        )
        # Chat also blocked by shared account quota
        denied_chat = await client.post(
            "/api/v1/ai/chat",
            json={"message": "hi"},
        )
    assert denied.status_code == 429
    assert denied_chat.status_code == 429
    assert calls["n"] == 3


@pytest.mark.anyio
async def test_ai009_report_does_not_consume_ai_quota(monkeypatch):
    """Content report is not an AI provider call — must not consume quota."""
    user = _user(1)
    app = _ai_app(user)

    monkeypatch.setattr(ai_route, "log_error_to_db", AsyncMock())
    monkeypatch.setattr(ai_route, "send_alert_email", AsyncMock())

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for _ in range(5):
            resp = await client.post(
                "/api/v1/ai/report",
                json={"reason": "offensive_or_unsafe"},
            )
            assert resp.status_code == 200
        # Quota still fully available for chat
        decision = await AiQuotaService.enforce(1)
        assert decision.remaining == 2


@pytest.mark.anyio
async def test_ai009_family_member_id_not_quota_owner(monkeypatch):
    """Family context must not create a separate quota pool / bypass."""
    user = _user(1)
    app = _ai_app(user)

    async def _fake_chat(*args, **kwargs):
        return "ok"

    monkeypatch.setattr(ai_route, "chat_with_health_assistant", _fake_chat)
    monkeypatch.setattr(ai_route, "_ai_available", lambda: False)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for i in range(3):
            resp = await client.post(
                "/api/v1/ai/chat",
                json={"message": f"m{i}", "family_member_id": i + 1},
            )
            assert resp.status_code == 200
        blocked = await client.post(
            "/api/v1/ai/chat",
            json={"message": "bypass?", "family_member_id": 99},
        )
    assert blocked.status_code == 429


def test_ai009_config_defaults_documented():
    """Implementation defaults exist and are overridable settings fields."""
    assert hasattr(settings, "AI_QUOTA_LIMIT")
    assert hasattr(settings, "AI_QUOTA_WINDOW_SECONDS")
    assert int(settings.AI_QUOTA_LIMIT) >= 1
    assert int(settings.AI_QUOTA_WINDOW_SECONDS) >= 1
