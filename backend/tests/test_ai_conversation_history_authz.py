"""HN-AI-003 — AI conversation history ownership / authz."""
from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import ai_assistant as ai_route
from app.core.database import get_db
from app.core.deps import get_current_user


def _user(uid: int, email: str = "a@example.com"):
    return SimpleNamespace(
        id=uid,
        email=email,
        is_active=True,
        name="Test",
        age=30,
        gender="F",
        blood_group="O+",
        health_conditions="[]",
        allergies="[]",
    )


def _conv(*, cid: int, owner_id: int, title: str = "Hello"):
    return SimpleNamespace(
        id=cid,
        user_id=owner_id,
        title=title,
        context_type="general",
        messages='[{"role":"user","content":"Hello"},{"role":"assistant","content":"Hi"}]',
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )


@pytest.fixture
def app_factory():
    def _make(user):
        app = FastAPI()
        app.include_router(ai_route.router, prefix="/api/v1/ai")

        async def _override_user():
            return user

        async def _override_db():
            db = AsyncMock()
            yield db

        app.dependency_overrides[get_current_user] = _override_user
        app.dependency_overrides[get_db] = _override_db
        return app

    return _make


def _db_returning(rows):
    """Build AsyncMock db whose execute().scalars().all() returns rows."""
    db = AsyncMock()
    result = MagicMock()
    result.scalars.return_value.all.return_value = rows
    result.scalar_one_or_none.return_value = rows[0] if len(rows) == 1 else None
    db.execute = AsyncMock(return_value=result)
    return db


@pytest.mark.anyio
async def test_ai_hist_01_owner_can_list_own_conversations(app_factory):
    """AI-HIST-01 / AI-HIST-08"""
    owner = _user(1)
    app = app_factory(owner)
    own = [_conv(cid=10, owner_id=1, title="Mine")]

    async def _db():
        db = AsyncMock()
        result = MagicMock()
        result.scalars.return_value.all.return_value = own
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/ai/conversations")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    assert data[0]["id"] == 10
    assert data[0]["title"] == "Mine"
    assert "messages" not in data[0]
    assert "content" not in data[0]


@pytest.mark.anyio
async def test_ai_hist_05_06_owner_can_get_own_conversation(app_factory):
    """AI-HIST-05 / AI-HIST-06"""
    owner = _user(1)
    app = app_factory(owner)
    conv = _conv(cid=10, owner_id=1)

    async def _db():
        db = AsyncMock()
        result = MagicMock()
        result.scalar_one_or_none.return_value = conv
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/ai/conversations/10")
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == 10
    assert isinstance(body["messages"], list)


@pytest.mark.anyio
async def test_ai_hist_07_08_user_cannot_open_other_users_conversation(app_factory):
    """AI-HIST-07 / AI-HIST-08 — cross-user get returns 404 (owner filter)."""
    user_b = _user(2, email="b@example.com")
    app = app_factory(user_b)

    async def _db():
        db = AsyncMock()
        result = MagicMock()
        # Query includes user_id == current_user.id → no row for B looking up A's id
        result.scalar_one_or_none.return_value = None
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/ai/conversations/10")
    assert resp.status_code == 404
    assert resp.json()["detail"] == "Conversation not found"


@pytest.mark.anyio
async def test_ai_hist_08_list_only_returns_current_user_rows(app_factory):
    """Cross-user: list endpoint only sees rows returned for current user filter."""
    user_a = _user(1)
    app = app_factory(user_a)
    # Simulate DB already filtered by user_id == 1
    own_only = [_conv(cid=1, owner_id=1, title="A")]

    async def _db():
        db = AsyncMock()
        result = MagicMock()
        result.scalars.return_value.all.return_value = own_only
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/ai/conversations")
    assert resp.status_code == 200
    ids = [c["id"] for c in resp.json()]
    assert ids == [1]


@pytest.mark.anyio
async def test_ai_hist_09_unauthenticated_rejected():
    """AI-HIST-09"""
    app = FastAPI()
    app.include_router(ai_route.router, prefix="/api/v1/ai")

    async def _db():
        db = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/ai/conversations")
    assert resp.status_code in (401, 403, 422)


@pytest.mark.anyio
async def test_ai_hist_12_list_payload_has_no_message_bodies(app_factory):
    """AI-HIST-12"""
    owner = _user(1)
    app = app_factory(owner)
    own = [_conv(cid=5, owner_id=1, title="Side effects question")]

    async def _db():
        db = AsyncMock()
        result = MagicMock()
        result.scalars.return_value.all.return_value = own
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/ai/conversations")
    row = resp.json()[0]
    assert set(row.keys()) >= {"id", "title", "message_count", "created_at", "updated_at"}
    assert "messages" not in row
    assert "Hello" not in str(row)  # message body must not appear in list row
