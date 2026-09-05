"""HN-FAMILY-009 — family-linked reminder ownership + name resolution."""
from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.api.routes import reminders as rem_route
from app.core.deps import get_current_user
from app.core.database import get_db
from app.schemas.medication import MedicationScheduleCreate, MedicationScheduleUpdate


def _user(uid: int = 1):
    return SimpleNamespace(id=uid, email=f"u{uid}@ex.com", is_active=True, token_version=0)


def _member(mid: int, owner_id: int, name: str = "Alex", active: bool = True):
    return SimpleNamespace(
        id=mid,
        user_id=owner_id,
        name=name,
        is_active=active,
    )


def _schedule(
    sid: int = 10,
    owner_id: int = 1,
    fm_id: int | None = None,
    medicine: str = "Metformin",
    active: bool = True,
):
    return SimpleNamespace(
        id=sid,
        user_id=owner_id,
        family_member_id=fm_id,
        medicine_name=medicine,
        dosage="500mg",
        frequency="daily",
        times='["08:00"]',
        instructions=None,
        start_date=None,
        end_date=None,
        refill_date=None,
        total_quantity=None,
        remaining_quantity=None,
        is_active=active,
        prescription_id=None,
        created_at=datetime.now(timezone.utc),
    )


@pytest.fixture
def rem_app():
    def _make(user):
        app = FastAPI()
        app.include_router(rem_route.router, prefix="/api/v1/reminders")

        async def _override_user():
            return user

        async def _override_db():
            db = AsyncMock()
            yield db

        app.dependency_overrides[get_current_user] = _override_user
        app.dependency_overrides[get_db] = _override_db
        return app

    return _make


@pytest.mark.anyio
async def test_family_rem_sec_01_personal_create(rem_app):
    """FAMILY-REM-SEC-01 / 12"""
    user = _user(1)
    app = rem_app(user)

    async def override_db():
        db = AsyncMock()
        db.add = MagicMock()
        db.commit = AsyncMock()

        async def refresh(obj):
            obj.id = 50
            obj.is_active = True
            obj.created_at = datetime.now(timezone.utc)

        db.refresh = AsyncMock(side_effect=refresh)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch.object(rem_route, "_require_owned_active_family_member") as req:
            resp = await client.post(
                "/api/v1/reminders/",
                json={
                    "medicine_name": "Metformin",
                    "frequency": "daily",
                    "times": ["08:00"],
                },
            )
            req.assert_not_called()
    assert resp.status_code == 200
    body = resp.json()
    assert body["family_member_id"] is None
    assert body.get("family_member_name") is None
    assert "family_member_name" in body


@pytest.mark.anyio
async def test_family_rem_sec_02_owned_member_create(rem_app):
    """FAMILY-REM-SEC-02 / 10"""
    user = _user(1)
    app = rem_app(user)
    member = _member(5, 1, "John")

    async def override_db():
        db = AsyncMock()
        db.add = MagicMock()
        db.commit = AsyncMock()

        async def refresh(obj):
            obj.id = 70
            obj.is_active = True
            obj.created_at = datetime.now(timezone.utc)

        db.refresh = AsyncMock(side_effect=refresh)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch.object(
            rem_route,
            "_require_owned_active_family_member",
            AsyncMock(return_value=member),
        ):
            resp = await client.post(
                "/api/v1/reminders/",
                json={
                    "medicine_name": "Metformin",
                    "frequency": "daily",
                    "times": ["08:00"],
                    "family_member_id": 5,
                },
            )
    assert resp.status_code == 200
    body = resp.json()
    assert body["family_member_id"] == 5
    assert body["family_member_name"] == "John"


@pytest.mark.anyio
async def test_family_rem_sec_03_04_14_cross_user_rejected(rem_app):
    """FAMILY-REM-SEC-03 / 04 / 14"""
    user = _user(1)
    app = rem_app(user)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch.object(
            rem_route,
            "_require_owned_active_family_member",
            AsyncMock(
                side_effect=HTTPException(status_code=404, detail="Family member not found")
            ),
        ):
            resp = await client.post(
                "/api/v1/reminders/",
                json={
                    "medicine_name": "Metformin",
                    "frequency": "daily",
                    "times": ["08:00"],
                    "family_member_id": 999,
                },
            )
    assert resp.status_code == 404
    detail = str(resp.json().get("detail", "")).lower()
    assert "family member not found" in detail
    assert "user" not in detail or "another" not in detail


@pytest.mark.anyio
async def test_family_rem_sec_05_update_cross_user_rejected(rem_app):
    """FAMILY-REM-SEC-05"""
    user = _user(1)
    app = rem_app(user)
    sched = _schedule(fm_id=5)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch.object(
            rem_route, "_get_schedule", AsyncMock(return_value=sched)
        ), patch.object(
            rem_route,
            "_require_owned_active_family_member",
            AsyncMock(
                side_effect=HTTPException(status_code=404, detail="Family member not found")
            ),
        ):
            resp = await client.put(
                "/api/v1/reminders/10",
                json={"family_member_id": 888},
            )
    assert resp.status_code == 404


@pytest.mark.anyio
async def test_family_rem_sec_06_07_08_15_owner_scoping(rem_app):
    """FAMILY-REM-SEC-06 / 07 / 08 / 15"""
    user = _user(2)
    app = rem_app(user)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch.object(
            rem_route,
            "_get_schedule",
            AsyncMock(
                side_effect=HTTPException(status_code=404, detail="Reminder not found")
            ),
        ):
            g = await client.get("/api/v1/reminders/10")
            d = await client.delete("/api/v1/reminders/10")
            u = await client.put("/api/v1/reminders/10", json={"is_active": False})
    assert g.status_code == 404
    assert d.status_code == 404
    assert u.status_code == 404


@pytest.mark.anyio
async def test_family_rem_sec_09_unauthenticated(rem_app):
    """FAMILY-REM-SEC-09"""
    app = FastAPI()
    app.include_router(rem_route.router, prefix="/api/v1/reminders")

    async def override_db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/reminders/")
    assert resp.status_code in (401, 403)


def test_family_rem_sec_11_create_schema_ignores_client_name():
    """FAMILY-REM-SEC-11: client cannot supply family_member_name on create."""
    fields = MedicationScheduleCreate.model_fields
    assert "family_member_name" not in fields
    assert "family_member_id" in fields
    assert "family_member_name" not in MedicationScheduleUpdate.model_fields


@pytest.mark.anyio
async def test_family_rem_sec_13_inactive_member_rejected(rem_app):
    """FAMILY-REM-SEC-13"""
    user = _user(1)
    app = rem_app(user)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch.object(
            rem_route,
            "_require_owned_active_family_member",
            AsyncMock(
                side_effect=HTTPException(status_code=404, detail="Family member not found")
            ),
        ):
            resp = await client.post(
                "/api/v1/reminders/",
                json={
                    "medicine_name": "Aspirin",
                    "frequency": "daily",
                    "times": ["09:00"],
                    "family_member_id": 3,
                },
            )
    assert resp.status_code == 404


@pytest.mark.anyio
async def test_require_owned_active_family_member_filters_owner():
    """Direct helper: wrong owner / inactive → 404."""
    db = AsyncMock()
    result = MagicMock()
    result.scalar_one_or_none.return_value = None
    db.execute = AsyncMock(return_value=result)
    with pytest.raises(HTTPException) as exc:
        await rem_route._require_owned_active_family_member(db, 1, 99)
    assert exc.value.status_code == 404
