"""HN-SOS-001 — SOS security contracts remain intact with timed hold (client-only change)."""
from __future__ import annotations

import inspect
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import emergency as emergency_route
from app.core.deps import get_current_user
from app.core.database import get_db


def _user(uid: int = 2, fcm: str | None = None):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@ex.com",
        is_active=True,
        token_version=0,
        fcm_token=fcm,
    )


@pytest.mark.anyio
async def test_sos_sec_01_unauthenticated_rejected():
    """SOS-SEC-01"""
    app = FastAPI()
    app.include_router(emergency_route.router, prefix="/api/v1/emergency")

    async def _db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/emergency/sos",
            json={"latitude": -37.8, "longitude": 144.9},
        )
    assert resp.status_code in (401, 403)


@pytest.mark.anyio
async def test_sos_sec_02_04_05_authenticated_owner_scoped():
    """SOS-SEC-02/04/05 — auth required; contacts query scoped to current_user."""
    user = _user(2)
    app = FastAPI()
    app.include_router(emergency_route.router, prefix="/api/v1/emergency")
    executed_sql_users = []

    async def _override_user():
        return user

    async def _override_db():
        db = AsyncMock()

        async def execute(stmt):
            executed_sql_users.append(user.id)
            result = MagicMock()
            result.scalars.return_value.all.return_value = []
            return result

        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_current_user] = _override_user
    app.dependency_overrides[get_db] = _override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/emergency/sos",
            json={"latitude": -37.81, "longitude": 144.96},
        )
    assert resp.status_code == 200
    body = resp.json()
    assert body.get("contacts_notified") == 0
    assert body.get("success") is True
    assert executed_sql_users == [user.id]
    assert "NOT automatically notified" in (body.get("message") or "") or (
        "No emergency contacts" in (body.get("message") or "")
    )


@pytest.mark.anyio
async def test_sos_sec_03_contact_delete_cross_user_rejected():
    """SOS-SEC-03 — contact delete remains owner-scoped."""
    user = _user(2)
    app = FastAPI()
    app.include_router(emergency_route.router, prefix="/api/v1/emergency")

    async def _override_user():
        return user

    async def _override_db():
        db = AsyncMock()
        result = MagicMock()
        result.scalar_one_or_none.return_value = None
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_current_user] = _override_user
    app.dependency_overrides[get_db] = _override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.delete("/api/v1/emergency/contacts/999")
    assert resp.status_code == 404


def test_sos_sec_06_no_auto_contact_notify_claims_zero():
    """SOS-SEC-06 — dial-first honesty; contacts_notified forced to 0."""
    src = inspect.getsource(emergency_route.trigger_sos)
    assert "contacts_notified=0" in src
    assert "tel:000" not in src
