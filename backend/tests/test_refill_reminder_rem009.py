"""HN-REM-009 — refill_date create/update + ownership regression."""
from __future__ import annotations

from datetime import date, datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.api.routes import reminders as rem_route
from app.core.deps import get_current_user
from app.core.database import get_db


def _user(uid: int = 1):
    return SimpleNamespace(id=uid, email=f"u{uid}@ex.com", is_active=True, token_version=0)


def _schedule(
    sid: int = 10,
    owner_id: int = 1,
    fm_id: int | None = None,
    medicine: str = "Metformin",
    refill: date | None = None,
    total_qty: int | None = None,
    remaining_qty: int | None = None,
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
        start_date=date(2026, 9, 1),
        end_date=None,
        refill_date=refill,
        total_quantity=total_qty,
        remaining_quantity=remaining_qty,
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
async def test_rem9_01_create_with_refill_date(rem_app):
    """REM9-01 Create reminder with refill_date persists."""
    user = _user(1)
    app = rem_app(user)
    captured = {}

    async def override_db():
        db = AsyncMock()
        db.add = MagicMock(side_effect=lambda obj: captured.setdefault("obj", obj))
        db.commit = AsyncMock()

        async def refresh(obj):
            obj.id = 101
            obj.is_active = True
            obj.created_at = datetime.now(timezone.utc)

        db.refresh = AsyncMock(side_effect=refresh)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/reminders/",
            json={
                "medicine_name": "Amoxicillin",
                "dosage": "250mg",
                "frequency": "daily",
                "times": ["08:00"],
                "refill_date": "2026-10-15",
                "total_quantity": 30,
                "remaining_quantity": 28,
            },
        )
    assert resp.status_code == 200
    body = resp.json()
    assert body["refill_date"] == "2026-10-15"
    assert body["total_quantity"] == 30
    assert captured["obj"].refill_date == date(2026, 10, 15)


@pytest.mark.anyio
async def test_rem9_02_create_without_refill_date(rem_app):
    """REM9-02 Create without refill_date remains valid."""
    user = _user(1)
    app = rem_app(user)

    async def override_db():
        db = AsyncMock()
        db.add = MagicMock()
        db.commit = AsyncMock()

        async def refresh(obj):
            obj.id = 102
            obj.is_active = True
            obj.created_at = datetime.now(timezone.utc)
            if not hasattr(obj, "refill_date"):
                obj.refill_date = None

        db.refresh = AsyncMock(side_effect=refresh)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/reminders/",
            json={
                "medicine_name": "Ibuprofen",
                "dosage": "200mg",
                "frequency": "twice_daily",
                "times": ["08:00", "20:00"],
            },
        )
    assert resp.status_code == 200
    assert resp.json().get("refill_date") is None


@pytest.mark.anyio
async def test_rem9_03_update_refill_date(rem_app):
    """REM9-03 Update reminder with refill_date persists."""
    user = _user(1)
    app = rem_app(user)
    schedule = _schedule(sid=55, refill=date(2026, 9, 20))

    async def override_db():
        db = AsyncMock()
        db.commit = AsyncMock()
        db.refresh = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch.object(rem_route, "_get_schedule", AsyncMock(return_value=schedule)):
            with patch.object(
                rem_route, "_family_names_for_schedules", AsyncMock(return_value={})
            ):
                resp = await client.put(
                    "/api/v1/reminders/55",
                    json={"refill_date": "2026-11-01"},
                )
    assert resp.status_code == 200
    assert schedule.refill_date == date(2026, 11, 1)
    assert resp.json()["refill_date"] == "2026-11-01"


@pytest.mark.anyio
async def test_rem9_04_clear_refill_date(rem_app):
    """REM9-04 Update clearing refill_date persists null."""
    user = _user(1)
    app = rem_app(user)
    schedule = _schedule(sid=56, refill=date(2026, 9, 20))

    async def override_db():
        db = AsyncMock()
        db.commit = AsyncMock()
        db.refresh = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch.object(rem_route, "_get_schedule", AsyncMock(return_value=schedule)):
            with patch.object(
                rem_route, "_family_names_for_schedules", AsyncMock(return_value={})
            ):
                resp = await client.put(
                    "/api/v1/reminders/56",
                    json={"refill_date": None},
                )
    assert resp.status_code == 200
    assert schedule.refill_date is None
    assert resp.json()["refill_date"] is None


@pytest.mark.anyio
async def test_rem9_05_quantity_on_create_and_update(rem_app):
    """REM9-05 Quantity / total_quantity behavior remains correct."""
    user = _user(1)
    app = rem_app(user)
    schedule = _schedule(sid=57, total_qty=20, remaining_qty=15)

    async def override_db():
        db = AsyncMock()
        db.add = MagicMock()
        db.commit = AsyncMock()

        async def refresh(obj):
            obj.id = 103
            obj.is_active = True
            obj.created_at = datetime.now(timezone.utc)

        db.refresh = AsyncMock(side_effect=refresh)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        create = await client.post(
            "/api/v1/reminders/",
            json={
                "medicine_name": "Vitamin D",
                "dosage": "1000IU",
                "frequency": "daily",
                "times": ["09:00"],
                "total_quantity": 60,
                "remaining_quantity": 55,
            },
        )
        assert create.status_code == 200
        assert create.json()["total_quantity"] == 60
        assert create.json()["remaining_quantity"] == 55

        with patch.object(rem_route, "_get_schedule", AsyncMock(return_value=schedule)):
            with patch.object(
                rem_route, "_family_names_for_schedules", AsyncMock(return_value={})
            ):
                upd = await client.put(
                    "/api/v1/reminders/57",
                    json={"total_quantity": 40, "remaining_quantity": 10},
                )
        assert upd.status_code == 200
        assert schedule.total_quantity == 40
        assert schedule.remaining_quantity == 10


@pytest.mark.anyio
async def test_rem9_06_cross_user_family_ownership(rem_app):
    """REM9-06 Cross-user / family ownership rules remain enforced."""
    user = _user(1)
    app = rem_app(user)

    async def override_db():
        db = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        with patch.object(
            rem_route,
            "_require_owned_active_family_member",
            AsyncMock(
                side_effect=HTTPException(
                    status_code=404, detail="Family member not found"
                )
            ),
        ):
            resp = await client.post(
                "/api/v1/reminders/",
                json={
                    "medicine_name": "Foreign",
                    "dosage": "1",
                    "frequency": "daily",
                    "times": ["08:00"],
                    "family_member_id": 999,
                    "refill_date": "2026-12-01",
                },
            )
    assert resp.status_code == 404
