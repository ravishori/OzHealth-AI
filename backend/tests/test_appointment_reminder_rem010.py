"""HN-REM-010 — Appointment Reminder (REM10 backend contracts)."""
from __future__ import annotations

import os
from datetime import datetime, timezone, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from app.api.routes import appointments as appt_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.appointment import Appointment
from app.schemas.appointment import (
    AppointmentCreate,
    normalize_remind_before_minutes,
    ALLOWED_REMIND_BEFORE_MINUTES,
)


def _user(uid: int = 1):
    return SimpleNamespace(
        id=uid, email=f"u{uid}@ex.com", is_active=True, token_version=0
    )


def _member(mid: int, owner_id: int, name: str = "Child", active: bool = True):
    return SimpleNamespace(
        id=mid, user_id=owner_id, name=name, is_active=active
    )


def _appt(
    aid: int = 10,
    owner_id: int = 1,
    *,
    title: str = "GP visit",
    scheduled_at: datetime | None = None,
    remind: int = 60,
    fm_id: int | None = None,
    active: bool = True,
    notes: str | None = None,
):
    return SimpleNamespace(
        id=aid,
        user_id=owner_id,
        family_member_id=fm_id,
        title=title,
        scheduled_at=scheduled_at
        or (datetime.now(timezone.utc) + timedelta(days=2)),
        notes=notes,
        remind_before_minutes=remind,
        is_active=active,
        created_at=datetime.now(timezone.utc),
        updated_at=None,
    )


class ApptStore:
    def __init__(
        self,
        appointments: dict[int, SimpleNamespace] | None = None,
        members: dict[int, SimpleNamespace] | None = None,
    ):
        self.appointments = appointments or {}
        self.members = members or {}
        self.next_id = 100
        self.add_calls = 0
        self.commit_calls = 0

    def _params(self, stmt) -> dict:
        try:
            return dict(stmt.compile().params or {})
        except Exception:
            return {}

    async def execute(self, stmt):
        text = str(stmt).lower()
        params = self._params(stmt)
        result = MagicMock()

        if "family_members" in text:
            mid = None
            uid = None
            for k, v in params.items():
                kl = str(k).lower()
                if "user" in kl and isinstance(v, int):
                    uid = v
                elif isinstance(v, int) and mid is None:
                    mid = v
            member = self.members.get(mid) if mid is not None else None
            if member is not None and uid is not None and member.user_id != uid:
                member = None
            if member is not None and not member.is_active:
                member = None
            # IN list for names
            if " in (" in text or " in(" in text:
                owned = [
                    m
                    for m in self.members.values()
                    if uid is None or m.user_id == uid
                ]
                result.scalars.return_value.all.return_value = owned
                result.scalar_one_or_none.return_value = None
                return result
            result.scalar_one_or_none.return_value = member
            return result

        if "appointments" in text:
            uid = None
            aid = None
            fmid = None
            for k, v in params.items():
                kl = str(k).lower()
                if "user" in kl and isinstance(v, int):
                    uid = v
                if kl == "id" or kl.endswith("_id") and "family" not in kl and "user" not in kl:
                    if isinstance(v, int) and "schedule" not in kl:
                        # prefer explicit id
                        if kl == "id" or "appointment" in kl:
                            aid = v
                if "family" in kl and isinstance(v, int):
                    fmid = v
            # Heuristic: ints without user key
            for k, v in params.items():
                if str(k).lower() == "id_1" and isinstance(v, int):
                    aid = v

            rows = list(self.appointments.values())
            if uid is not None:
                rows = [a for a in rows if a.user_id == uid]
            if fmid is not None:
                rows = [a for a in rows if a.family_member_id == fmid]
            if "is_active" in text or "true" in text:
                # active_only filter often present
                if "is_active" in text:
                    rows = [a for a in rows if a.is_active]

            if aid is not None and ("where" in text):
                match = self.appointments.get(aid)
                if match is not None and uid is not None and match.user_id != uid:
                    match = None
                result.scalar_one_or_none.return_value = match
                result.scalars.return_value.all.return_value = (
                    [match] if match else []
                )
                return result

            rows.sort(key=lambda a: a.scheduled_at)
            result.scalars.return_value.all.return_value = rows
            result.scalar_one_or_none.return_value = (
                rows[0] if len(rows) == 1 else None
            )
            return result

        result.scalar_one_or_none.return_value = None
        result.scalars.return_value.all.return_value = []
        return result

    def add(self, obj):
        self.add_calls += 1
        if isinstance(obj, Appointment):
            if getattr(obj, "id", None) is None:
                obj.id = self.next_id
                self.next_id += 1
            if getattr(obj, "created_at", None) is None:
                obj.created_at = datetime.now(timezone.utc)
            if getattr(obj, "is_active", None) is None:
                obj.is_active = True
            self.appointments[obj.id] = obj

    async def commit(self):
        self.commit_calls += 1
        # Sync ORM objects into store after mutations
        for aid, a in list(self.appointments.items()):
            if isinstance(a, Appointment) or hasattr(a, "is_active"):
                self.appointments[aid] = a

    async def refresh(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = self.next_id
            self.next_id += 1
        if getattr(obj, "created_at", None) is None:
            obj.created_at = datetime.now(timezone.utc)
        if getattr(obj, "is_active", None) is None:
            obj.is_active = True
        self.appointments[obj.id] = obj


def _app(user=None, store: ApptStore | None = None):
    app = FastAPI()
    app.include_router(appt_route.router, prefix="/api/v1/appointments")
    store = store or ApptStore()

    async def _override_db():
        yield store

    app.dependency_overrides[get_db] = _override_db
    if user is not None:

        async def _override_user():
            return user

        app.dependency_overrides[get_current_user] = _override_user
    return app, store


def _when(days: int = 3) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()


# ── Schema ────────────────────────────────────────────────────────────────────


def test_remind_before_accepts_allowed():
    for m in ALLOWED_REMIND_BEFORE_MINUTES:
        assert normalize_remind_before_minutes(m) == m


def test_remind_before_rejects_invalid():
    with pytest.raises(ValueError):
        normalize_remind_before_minutes(45)


def test_create_schema_rejects_empty_title():
    with pytest.raises(ValidationError):
        AppointmentCreate(
            title="  ",
            scheduled_at=datetime.now(timezone.utc) + timedelta(days=1),
        )


# ── REM10-01 create ───────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rem10_01_authenticated_create():
    user = _user(1)
    app, store = _app(user)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/appointments/",
            json={
                "title": "Dentist",
                "scheduled_at": _when(5),
                "remind_before_minutes": 30,
                "notes": "Bring card",
            },
        )
    assert resp.status_code == 201
    body = resp.json()
    assert body["title"] == "Dentist"
    assert body["user_id"] == 1
    assert body["remind_before_minutes"] == 30
    assert body["is_active"] is True
    assert store.add_calls == 1


# ── REM10-02 list ─────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rem10_02_authenticated_list():
    user = _user(1)
    store = ApptStore(
        appointments={
            1: _appt(1, 1, title="A", scheduled_at=datetime.now(timezone.utc) + timedelta(days=1)),
            2: _appt(2, 1, title="B", scheduled_at=datetime.now(timezone.utc) + timedelta(days=3)),
            3: _appt(3, 2, title="Other"),
        }
    )
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/appointments/")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 2
    assert body[0]["title"] == "A"
    assert body[1]["title"] == "B"


# ── REM10-03 get ──────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rem10_03_authenticated_get():
    user = _user(1)
    store = ApptStore(appointments={10: _appt(10, 1, title="Physio")})
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/appointments/10")
    assert resp.status_code == 200
    assert resp.json()["title"] == "Physio"


# ── REM10-04 update ───────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rem10_04_authenticated_update():
    user = _user(1)
    appt = _appt(10, 1, title="Old", remind=60)
    store = ApptStore(appointments={10: appt})
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.put(
            "/api/v1/appointments/10",
            json={"title": "New title", "remind_before_minutes": 15},
        )
    assert resp.status_code == 200
    assert resp.json()["title"] == "New title"
    assert resp.json()["remind_before_minutes"] == 15
    assert appt.title == "New title"


# ── REM10-05 delete ───────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rem10_05_authenticated_delete_soft():
    user = _user(1)
    appt = _appt(10, 1)
    store = ApptStore(appointments={10: appt})
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.delete("/api/v1/appointments/10")
    assert resp.status_code == 200
    assert appt.is_active is False


# ── REM10-06 unauthenticated ──────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rem10_06_unauthenticated_rejected():
    app, _ = _app(user=None)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        r1 = await client.get("/api/v1/appointments/")
        r2 = await client.post(
            "/api/v1/appointments/",
            json={"title": "X", "scheduled_at": _when()},
        )
    assert r1.status_code in (401, 403)
    assert r2.status_code in (401, 403)


# ── REM10-07/08/09 cross-user ─────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rem10_07_08_09_cross_user_isolation():
    user_a = _user(1)
    store = ApptStore(appointments={99: _appt(99, 2, title="Secret")})
    app, store = _app(user_a, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        g = await client.get("/api/v1/appointments/99")
        u = await client.put("/api/v1/appointments/99", json={"title": "Hacked"})
        d = await client.delete("/api/v1/appointments/99")
        listed = await client.get("/api/v1/appointments/")
    assert g.status_code == 404
    assert u.status_code == 404
    assert d.status_code == 404
    assert listed.json() == []
    assert store.appointments[99].title == "Secret"
    assert store.appointments[99].is_active is True


# ── REM10-10/11 invalid data ──────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rem10_10_11_invalid_data_and_remind():
    user = _user(1)
    app, _ = _app(user)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        bad_title = await client.post(
            "/api/v1/appointments/",
            json={"title": "", "scheduled_at": _when()},
        )
        bad_remind = await client.post(
            "/api/v1/appointments/",
            json={
                "title": "Valid",
                "scheduled_at": _when(),
                "remind_before_minutes": 7,
            },
        )
    assert bad_title.status_code == 422
    assert bad_remind.status_code == 422


# ── REM10-12 ownership on create ignores client user_id ───────────────────────


@pytest.mark.anyio
async def test_rem10_12_client_user_id_ignored():
    user = _user(1)
    app, store = _app(user)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/appointments/",
            json={
                "title": "Checkup",
                "scheduled_at": _when(),
                "user_id": 999,
                "owner_id": 999,
            },
        )
    assert resp.status_code == 201
    assert resp.json()["user_id"] == 1
    saved = next(iter(store.appointments.values()))
    assert saved.user_id == 1


# ── REM10-13 family ownership ─────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rem10_13_family_member_ownership():
    user = _user(1)
    store = ApptStore(members={5: _member(5, 1), 9: _member(9, 2)})
    app, store = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        ok = await client.post(
            "/api/v1/appointments/",
            json={
                "title": "Child GP",
                "scheduled_at": _when(),
                "family_member_id": 5,
            },
        )
        bad = await client.post(
            "/api/v1/appointments/",
            json={
                "title": "Steal",
                "scheduled_at": _when(),
                "family_member_id": 9,
            },
        )
    assert ok.status_code == 201
    assert ok.json()["family_member_id"] == 5
    assert bad.status_code == 404


# ── Notification contract markers (Flutter schedules locally) ─────────────────


def test_rem10_14_15_16_notification_id_namespace_documented():
    """Medication uses scheduleId*10; appointments use 2_000_000+id."""
    from pathlib import Path

    notif = Path(
        __file__
    ).resolve().parents[2] / "flutter_app" / "lib" / "core" / "notifications" / "local_reminder_notifications.dart"
    # When running from backend/tests, parents[1]=backend, parents[2]=repo root
    repo = Path(__file__).resolve().parents[2]
    notif = repo / "flutter_app" / "lib" / "core" / "notifications" / "local_reminder_notifications.dart"
    src = notif.read_text()
    assert "appointmentNotificationId" in src
    assert "2000000" in src or "2_000_000" in src
    assert "scheduleAppointmentReminder" in src
    assert "cancelAppointmentNotification" in src
    # Medication refill formula still present (regression)
    assert "scheduleId * 10 + 9" in src
    assert "cancelForSchedule" in src
