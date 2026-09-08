"""HN-MEDMGMT-006 — Medication History (MEDHIST-01..22)."""
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

from app.api.routes import medication_history as hist_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.medication_dose_event import MedicationDoseEvent
from app.schemas.medication_history import (
    MedicationDoseEventCreate,
    normalize_dose_status,
)


def _user(uid: int = 1):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@ex.com",
        is_active=True,
        token_version=0,
    )


def _member(mid: int, owner_id: int, name: str = "Child", active: bool = True):
    return SimpleNamespace(
        id=mid,
        user_id=owner_id,
        name=name,
        is_active=active,
    )


def _schedule(
    sid: int = 10,
    owner_id: int = 1,
    *,
    medicine: str = "Paracetamol",
    dosage: str = "500mg",
    fm_id: int | None = None,
    frequency: str = "daily",
    times: str = '["08:00"]',
    active: bool = True,
):
    return SimpleNamespace(
        id=sid,
        user_id=owner_id,
        family_member_id=fm_id,
        medicine_name=medicine,
        dosage=dosage,
        frequency=frequency,
        times=times,
        instructions=None,
        start_date=None,
        end_date=None,
        refill_date=None,
        total_quantity=None,
        remaining_quantity=None,
        is_active=active,
        prescription_id=None,
        created_at=datetime.now(timezone.utc),
        updated_at=None,
    )


def _event(
    eid: int,
    *,
    user_id: int,
    schedule_id: int,
    status: str,
    scheduled_for: datetime,
    recorded_at: datetime | None = None,
    family_member_id: int | None = None,
):
    return SimpleNamespace(
        id=eid,
        user_id=user_id,
        medication_schedule_id=schedule_id,
        family_member_id=family_member_id,
        status=status,
        scheduled_for=scheduled_for,
        recorded_at=recorded_at or datetime.now(timezone.utc),
        created_at=datetime.now(timezone.utc),
        updated_at=None,
    )


class DoseStore:
    """In-memory stand-in for schedules + dose events."""

    def __init__(
        self,
        schedules: dict[int, SimpleNamespace] | None = None,
        members: dict[int, SimpleNamespace] | None = None,
    ):
        self.schedules = schedules or {}
        self.members = members or {}
        self.events: dict[int, SimpleNamespace] = {}
        self.next_id = 1
        self.add_calls = 0
        self.commit_calls = 0
        self.delete_calls = 0

    def _params(self, stmt) -> dict:
        try:
            return dict(stmt.compile().params or {})
        except Exception:
            return {}

    def _ints(self, params: dict) -> list[int]:
        return [v for v in params.values() if isinstance(v, int)]

    async def execute(self, stmt):
        text = str(stmt).lower()
        params = self._params(stmt)
        result = MagicMock()

        # Group-by summary
        if "group by" in text and "medication_dose_events" in text:
            uid = None
            for k, v in params.items():
                if "user" in str(k).lower() and isinstance(v, int):
                    uid = v
            rows = []
            counts: dict[str, int] = {}
            for e in self.events.values():
                if uid is not None and e.user_id != uid:
                    continue
                # Optional schedule / family filters
                sid = None
                fmid = None
                for k, v in params.items():
                    kl = str(k).lower()
                    if "schedule" in kl and isinstance(v, int):
                        sid = v
                    if "family" in kl and isinstance(v, int):
                        fmid = v
                if sid is not None and e.medication_schedule_id != sid:
                    continue
                if fmid is not None and e.family_member_id != fmid:
                    continue
                counts[e.status] = counts.get(e.status, 0) + 1
            rows = list(counts.items())
            result.all.return_value = rows
            return result

        # Family member ownership lookup
        if "family_members" in text:
            mid = None
            uid = None
            for k, v in params.items():
                kl = str(k).lower()
                if kl in ("id", "id_1", "family_members_id") or (
                    "id" in kl and "user" not in kl and isinstance(v, int)
                ):
                    if mid is None and isinstance(v, int):
                        mid = v
                if "user" in kl and isinstance(v, int):
                    uid = v
            ints = self._ints(params)
            if mid is None and ints:
                mid = ints[0]
            if uid is None and len(ints) >= 2:
                uid = ints[1]
            member = self.members.get(mid) if mid is not None else None
            if member is not None and uid is not None and member.user_id != uid:
                member = None
            if member is not None and not member.is_active:
                member = None
            result.scalar_one_or_none.return_value = member
            return result

        # Medication schedule lookup / label load
        if "medication_schedules" in text:
            sid = None
            uid = None
            for k, v in params.items():
                kl = str(k).lower()
                if "user" in kl and isinstance(v, int):
                    uid = v
                if ("id" in kl or "schedule" in kl) and isinstance(v, int):
                    if "user" not in kl:
                        sid = v
            # IN clause for multiple ids
            if "in (" in text or " in(" in text:
                owned = [
                    s
                    for s in self.schedules.values()
                    if uid is None or s.user_id == uid
                ]
                # Filter by ids present in params
                id_vals = [
                    v
                    for k, v in params.items()
                    if isinstance(v, int) and "user" not in str(k).lower()
                ]
                if id_vals:
                    owned = [s for s in owned if s.id in id_vals]
                result.scalars.return_value.all.return_value = owned
                result.scalar_one_or_none.return_value = owned[0] if len(owned) == 1 else None
                return result

            sched = self.schedules.get(sid) if sid is not None else None
            if sched is not None and uid is not None and sched.user_id != uid:
                sched = None
            result.scalar_one_or_none.return_value = sched
            result.scalars.return_value.all.return_value = [sched] if sched else []
            return result

        # Dose event queries
        if "medication_dose_events" in text:
            uid = None
            eid = None
            sid = None
            scheduled = None
            fmid = None
            for k, v in params.items():
                kl = str(k).lower()
                if "user" in kl and isinstance(v, int):
                    uid = v
                if kl in ("id", "id_1") or (
                    kl.endswith("_id") is False
                    and "id" == kl
                ):
                    pass
                if kl == "id" or kl.endswith(".id") or kl == "medication_dose_events_id":
                    if isinstance(v, int):
                        eid = v
                if "schedule" in kl and isinstance(v, int):
                    sid = v
                if "family" in kl and isinstance(v, int):
                    fmid = v
                if "scheduled" in kl and isinstance(v, datetime):
                    scheduled = v

            # List path
            if "order by" in text or (
                eid is None and scheduled is None and "count" not in text
            ):
                events = list(self.events.values())
                if uid is not None:
                    events = [e for e in events if e.user_id == uid]
                if sid is not None:
                    events = [
                        e for e in events if e.medication_schedule_id == sid
                    ]
                if fmid is not None:
                    events = [e for e in events if e.family_member_id == fmid]
                events.sort(
                    key=lambda e: (e.recorded_at, e.id),
                    reverse=True,
                )
                # If looking up by scheduled_for + schedule
                if scheduled is not None and sid is not None:
                    match = next(
                        (
                            e
                            for e in events
                            if e.medication_schedule_id == sid
                            and e.scheduled_for == scheduled
                            and (uid is None or e.user_id == uid)
                        ),
                        None,
                    )
                    result.scalar_one_or_none.return_value = match
                    result.scalars.return_value.all.return_value = (
                        [match] if match else []
                    )
                    return result

                result.scalars.return_value.all.return_value = events
                result.scalar_one_or_none.return_value = (
                    events[0] if len(events) == 1 else None
                )
                return result

            # Single get by id
            if eid is not None:
                ev = self.events.get(eid)
                if ev is not None and uid is not None and ev.user_id != uid:
                    ev = None
                result.scalar_one_or_none.return_value = ev
                return result

            # Occurrence lookup
            if sid is not None and scheduled is not None:
                match = None
                for e in self.events.values():
                    if (
                        e.medication_schedule_id == sid
                        and e.scheduled_for == scheduled
                        and (uid is None or e.user_id == uid)
                    ):
                        match = e
                        break
                result.scalar_one_or_none.return_value = match
                return result

            result.scalar_one_or_none.return_value = None
            result.scalars.return_value.all.return_value = []
            return result

        result.scalar_one_or_none.return_value = None
        result.scalars.return_value.all.return_value = []
        result.all.return_value = []
        return result

    def add(self, obj):
        self.add_calls += 1
        if isinstance(obj, MedicationDoseEvent):
            if getattr(obj, "id", None) is None:
                obj.id = self.next_id
                self.next_id += 1
            if getattr(obj, "created_at", None) is None:
                obj.created_at = datetime.now(timezone.utc)
            if getattr(obj, "recorded_at", None) is None:
                obj.recorded_at = datetime.now(timezone.utc)
            # Store as SimpleNamespace-like via the ORM object itself
            self.events[obj.id] = obj

    async def commit(self):
        self.commit_calls += 1

    async def rollback(self):
        pass

    async def refresh(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = self.next_id
            self.next_id += 1
        if isinstance(obj, MedicationDoseEvent):
            if getattr(obj, "created_at", None) is None:
                obj.created_at = datetime.now(timezone.utc)
            self.events[obj.id] = obj

    async def delete(self, obj):
        self.delete_calls += 1
        eid = getattr(obj, "id", None)
        if eid in self.events:
            del self.events[eid]


def _app(user=None, store: DoseStore | None = None):
    app = FastAPI()
    app.include_router(
        hist_route.router, prefix="/api/v1/medication-history"
    )
    store = store or DoseStore()

    async def _override_db():
        yield store

    app.dependency_overrides[get_db] = _override_db
    if user is not None:

        async def _override_user():
            return user

        app.dependency_overrides[get_current_user] = _override_user
    return app, store


def _when(h: int = 8, m: int = 0, day: int = 8) -> datetime:
    return datetime(2026, 9, day, h, m, tzinfo=timezone.utc)


# ── Schema validation ─────────────────────────────────────────────────────────


def test_normalize_dose_status_accepts_known():
    assert normalize_dose_status("TAKEN") == "taken"
    assert normalize_dose_status("skipped") == "skipped"
    assert normalize_dose_status(" Missed ") == "missed"


def test_normalize_dose_status_rejects_unknown():
    with pytest.raises(ValueError):
        normalize_dose_status("maybe")


def test_create_schema_rejects_invalid_status():
    with pytest.raises(ValidationError):
        MedicationDoseEventCreate(
            medication_schedule_id=1,
            status="half",
            scheduled_for=_when(),
        )


# ── MEDHIST-01 TAKEN ──────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_01_record_taken():
    user = _user(1)
    store = DoseStore(schedules={10: _schedule(10, 1)})
    app, store = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "taken",
                "scheduled_for": _when().isoformat(),
            },
        )
    assert resp.status_code == 201
    body = resp.json()
    assert body["status"] == "taken"
    assert body["medication_schedule_id"] == 10
    assert body["medicine_name"] == "Paracetamol"
    assert body["duplicate"] is False
    assert store.add_calls == 1
    assert len(store.events) == 1


# ── MEDHIST-02 SKIPPED ────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_02_record_skipped():
    user = _user(1)
    app, store = _app(user, DoseStore(schedules={10: _schedule(10, 1)}))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "skipped",
                "scheduled_for": _when().isoformat(),
            },
        )
    assert resp.status_code == 201
    assert resp.json()["status"] == "skipped"


# ── MEDHIST-03 MISSED ─────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_03_record_missed():
    user = _user(1)
    app, store = _app(user, DoseStore(schedules={10: _schedule(10, 1)}))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "missed",
                "scheduled_for": _when().isoformat(),
            },
        )
    assert resp.status_code == 201
    assert resp.json()["status"] == "missed"


# ── MEDHIST-04 invalid status ─────────────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_04_invalid_status_rejected():
    user = _user(1)
    app, _ = _app(user, DoseStore(schedules={10: _schedule(10, 1)}))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "delayed",
                "scheduled_for": _when().isoformat(),
            },
        )
    assert resp.status_code == 422


# ── MEDHIST-05 unauthenticated ────────────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_05_unauthenticated_create_rejected():
    app, _ = _app(user=None)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "taken",
                "scheduled_for": _when().isoformat(),
            },
        )
    assert resp.status_code in (401, 403)


# ── MEDHIST-06 retrieve own history ───────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_06_retrieve_own_history():
    user = _user(1)
    store = DoseStore(schedules={10: _schedule(10, 1)})
    store.events[1] = _event(
        1,
        user_id=1,
        schedule_id=10,
        status="taken",
        scheduled_for=_when(),
        recorded_at=_when(9),
    )
    store.events[2] = _event(
        2,
        user_id=1,
        schedule_id=10,
        status="skipped",
        scheduled_for=_when(day=7),
        recorded_at=_when(10, day=7),
    )
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/medication-history/")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 2
    assert {e["status"] for e in body} == {"taken", "skipped"}


# ── MEDHIST-07 cannot retrieve User B ─────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_07_cannot_retrieve_other_user_history():
    user_a = _user(1)
    store = DoseStore(
        schedules={
            10: _schedule(10, 1),
            20: _schedule(20, 2, medicine="Ibuprofen"),
        }
    )
    store.events[1] = _event(
        1, user_id=1, schedule_id=10, status="taken", scheduled_for=_when()
    )
    store.events[2] = _event(
        2,
        user_id=2,
        schedule_id=20,
        status="taken",
        scheduled_for=_when(h=9),
    )
    app, _ = _app(user_a, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/medication-history/")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 1
    assert body[0]["medication_schedule_id"] == 10
    assert all(e["medicine_name"] != "Ibuprofen" or e["medication_schedule_id"] == 10 for e in body)


# ── MEDHIST-08 cannot create for User B medication ────────────────────────────


@pytest.mark.anyio
async def test_medhist_08_cannot_create_for_other_user_medication():
    user_a = _user(1)
    store = DoseStore(schedules={20: _schedule(20, 2)})
    app, store = _app(user_a, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 20,
                "status": "taken",
                "scheduled_for": _when().isoformat(),
            },
        )
    assert resp.status_code == 404
    assert store.add_calls == 0


# ── MEDHIST-09 cannot modify/delete User B history ────────────────────────────


@pytest.mark.anyio
async def test_medhist_09_cannot_delete_other_user_history():
    user_a = _user(1)
    store = DoseStore(schedules={20: _schedule(20, 2)})
    store.events[99] = _event(
        99, user_id=2, schedule_id=20, status="taken", scheduled_for=_when()
    )
    app, store = _app(user_a, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.delete("/api/v1/medication-history/99")
    assert resp.status_code == 404
    assert 99 in store.events
    assert store.delete_calls == 0


# ── MEDHIST-10 / 11 schedule + medication preservation ────────────────────────


@pytest.mark.anyio
async def test_medhist_10_11_history_does_not_mutate_schedule():
    user = _user(1)
    sched = _schedule(10, 1, medicine="Paracetamol", dosage="500mg")
    store = DoseStore(schedules={10: sched})
    app, store = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "taken",
                "scheduled_for": _when().isoformat(),
            },
        )
    assert resp.status_code == 201
    # Canonical schedule fields untouched
    assert store.schedules[10].medicine_name == "Paracetamol"
    assert store.schedules[10].dosage == "500mg"
    assert store.schedules[10].frequency == "daily"
    assert store.schedules[10].times == '["08:00"]'
    assert store.schedules[10].is_active is True


# ── MEDHIST-12 duplicate submission ───────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_12_duplicate_submission_idempotent():
    user = _user(1)
    app, store = _app(user, DoseStore(schedules={10: _schedule(10, 1)}))
    payload = {
        "medication_schedule_id": 10,
        "status": "taken",
        "scheduled_for": _when().isoformat(),
    }
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        r1 = await client.post("/api/v1/medication-history/", json=payload)
        r2 = await client.post("/api/v1/medication-history/", json=payload)
    assert r1.status_code == 201
    assert r2.status_code == 200
    assert r2.json()["duplicate"] is True
    assert r1.json()["id"] == r2.json()["id"]
    assert len(store.events) == 1
    assert store.add_calls == 1


@pytest.mark.anyio
async def test_medhist_12b_different_status_same_occurrence_conflict():
    user = _user(1)
    app, store = _app(user, DoseStore(schedules={10: _schedule(10, 1)}))
    when = _when().isoformat()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        r1 = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "taken",
                "scheduled_for": when,
            },
        )
        r2 = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "skipped",
                "scheduled_for": when,
            },
        )
    assert r1.status_code == 201
    assert r2.status_code == 409
    assert len(store.events) == 1


# ── MEDHIST-13 nonexistent medication ─────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_13_nonexistent_medication_rejected():
    user = _user(1)
    app, store = _app(user, DoseStore(schedules={}))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 999,
                "status": "taken",
                "scheduled_for": _when().isoformat(),
            },
        )
    assert resp.status_code == 404
    assert store.add_calls == 0


# ── MEDHIST-14 family-member ownership ────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_14_family_filter_enforced():
    user = _user(1)
    store = DoseStore(
        schedules={
            10: _schedule(10, 1, fm_id=5),
            11: _schedule(11, 1, medicine="VitD"),
        },
        members={5: _member(5, 1)},
    )
    store.events[1] = _event(
        1,
        user_id=1,
        schedule_id=10,
        status="taken",
        scheduled_for=_when(),
        family_member_id=5,
    )
    store.events[2] = _event(
        2,
        user_id=1,
        schedule_id=11,
        status="taken",
        scheduled_for=_when(h=9),
        family_member_id=None,
    )
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        ok = await client.get("/api/v1/medication-history/?family_member_id=5")
        bad = await client.get("/api/v1/medication-history/?family_member_id=99")
    assert ok.status_code == 200
    assert len(ok.json()) == 1
    assert ok.json()[0]["family_member_id"] == 5
    assert bad.status_code == 404


@pytest.mark.anyio
async def test_medhist_14b_family_member_copied_from_schedule():
    user = _user(1)
    store = DoseStore(
        schedules={10: _schedule(10, 1, fm_id=5)},
        members={5: _member(5, 1)},
    )
    app, store = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "taken",
                "scheduled_for": _when().isoformat(),
            },
        )
    assert resp.status_code == 201
    assert resp.json()["family_member_id"] == 5
    ev = next(iter(store.events.values()))
    assert ev.family_member_id == 5
    assert ev.user_id == 1


# ── MEDHIST-15 ordering ───────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_15_history_ordering_newest_first():
    user = _user(1)
    store = DoseStore(schedules={10: _schedule(10, 1)})
    older = _when(8, day=1)
    newer = _when(8, day=8)
    store.events[1] = _event(
        1,
        user_id=1,
        schedule_id=10,
        status="taken",
        scheduled_for=older,
        recorded_at=older,
    )
    store.events[2] = _event(
        2,
        user_id=1,
        schedule_id=10,
        status="missed",
        scheduled_for=newer,
        recorded_at=newer,
    )
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/medication-history/")
    assert resp.status_code == 200
    body = resp.json()
    assert body[0]["id"] == 2
    assert body[1]["id"] == 1


# ── Summary + filter by schedule ──────────────────────────────────────────────


@pytest.mark.anyio
async def test_adherence_summary_basic():
    user = _user(1)
    store = DoseStore(schedules={10: _schedule(10, 1)})
    store.events[1] = _event(
        1, user_id=1, schedule_id=10, status="taken", scheduled_for=_when(day=1)
    )
    store.events[2] = _event(
        2, user_id=1, schedule_id=10, status="taken", scheduled_for=_when(day=2)
    )
    store.events[3] = _event(
        3, user_id=1, schedule_id=10, status="skipped", scheduled_for=_when(day=3)
    )
    store.events[4] = _event(
        4, user_id=1, schedule_id=10, status="missed", scheduled_for=_when(day=4)
    )
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/medication-history/summary")
    assert resp.status_code == 200
    body = resp.json()
    assert body["taken"] == 2
    assert body["skipped"] == 1
    assert body["missed"] == 1
    assert body["total"] == 4
    assert body["adherence_percent"] == 50.0


@pytest.mark.anyio
async def test_filter_by_schedule_requires_ownership():
    user = _user(1)
    store = DoseStore(schedules={20: _schedule(20, 2)})
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get(
            "/api/v1/medication-history/?medication_schedule_id=20"
        )
    assert resp.status_code == 404


# ── MEDHIST-16 recorded_at server-controlled ───────────────────────────────────


@pytest.mark.anyio
async def test_medhist_16_recorded_at_server_controlled():
    """MEDHIST-16 — recorded_at is set by server; client cannot supply it."""
    user = _user(1)
    app, store = _app(user, DoseStore(schedules={10: _schedule(10, 1)}))
    transport = ASGITransport(app=app)
    client_ts = "2099-01-01T00:00:00+00:00"
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/medication-history/",
            json={
                "medication_schedule_id": 10,
                "status": "taken",
                "scheduled_for": _when().isoformat(),
                "recorded_at": client_ts,
                "user_id": 999,
            },
        )
    assert resp.status_code == 201
    body = resp.json()
    assert body["recorded_at"] != client_ts
    assert "2099" not in body["recorded_at"]
    assert body.get("user_id") is None or body.get("user_id") != 999
    # Ownership remains authenticated user.
    assert list(store.events.values())[0].user_id == 1


# ── MEDHIST-17 / 18 history owner-scoped + ordering ───────────────────────────


@pytest.mark.anyio
async def test_medhist_17_18_history_owner_scoped_and_ordered():
    """MEDHIST-17/18 — list is owner-scoped and newest recorded_at first."""
    user = _user(1)
    store = DoseStore(schedules={10: _schedule(10, 1), 20: _schedule(20, 2)})
    older = _when(day=1)
    newer = _when(day=5)
    store.events[1] = _event(
        1, user_id=1, schedule_id=10, status="taken", scheduled_for=older, recorded_at=older
    )
    store.events[2] = _event(
        2, user_id=1, schedule_id=10, status="skipped", scheduled_for=newer, recorded_at=newer
    )
    store.events[3] = _event(
        3, user_id=2, schedule_id=20, status="taken", scheduled_for=newer, recorded_at=newer
    )
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/medication-history/")
    assert resp.status_code == 200
    body = resp.json()
    assert all(e["medication_schedule_id"] != 20 for e in body)
    assert [e["id"] for e in body] == [2, 1]


# ── MEDHIST-19 filtering ──────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_19_history_filtering_by_schedule():
    """MEDHIST-19 — schedule filter works for owned schedules only."""
    user = _user(1)
    store = DoseStore(
        schedules={10: _schedule(10, 1), 11: _schedule(11, 1, medicine="Ibuprofen")}
    )
    store.events[1] = _event(
        1, user_id=1, schedule_id=10, status="taken", scheduled_for=_when(day=1)
    )
    store.events[2] = _event(
        2, user_id=1, schedule_id=11, status="skipped", scheduled_for=_when(day=2)
    )
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get(
            "/api/v1/medication-history/?medication_schedule_id=11"
        )
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 1
    assert body[0]["medication_schedule_id"] == 11
    assert body[0]["medicine_name"] == "Ibuprofen"


# ── MEDHIST-20 / 21 summary honesty ───────────────────────────────────────────


@pytest.mark.anyio
async def test_medhist_20_21_summary_uses_events_no_false_100():
    """MEDHIST-20/21 — summary from stored events; empty → adherence_percent null."""
    user = _user(1)
    empty_app, _ = _app(user, DoseStore(schedules={10: _schedule(10, 1)}))
    transport = ASGITransport(app=empty_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        empty = await client.get("/api/v1/medication-history/summary")
    assert empty.status_code == 200
    empty_body = empty.json()
    assert empty_body["total"] == 0
    assert empty_body["taken"] == 0
    assert empty_body["adherence_percent"] is None
    assert empty_body["adherence_percent"] != 100
    assert empty_body["adherence_percent"] != 100.0

    store = DoseStore(schedules={10: _schedule(10, 1)})
    store.events[1] = _event(
        1, user_id=1, schedule_id=10, status="taken", scheduled_for=_when(day=1)
    )
    store.events[2] = _event(
        2, user_id=1, schedule_id=10, status="missed", scheduled_for=_when(day=2)
    )
    app, _ = _app(user, store)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/medication-history/summary")
    body = resp.json()
    assert body["taken"] == 1
    assert body["missed"] == 1
    assert body["total"] == 2
    assert body["adherence_percent"] == 50.0


# ── MEDHIST-22 privacy logging + migration schema ─────────────────────────────


@pytest.mark.anyio
async def test_medhist_22_no_sensitive_logging_and_schema_contract(caplog):
    """MEDHIST-22 — create audit path does not log medicine names / status PHI."""
    import logging

    user = _user(1)
    store = DoseStore(schedules={10: _schedule(10, 1, medicine="SecretMedXYZ")})
    app, _ = _app(user, store)
    with caplog.at_level(logging.INFO):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/medication-history/",
                json={
                    "medication_schedule_id": 10,
                    "status": "taken",
                    "scheduled_for": _when().isoformat(),
                },
            )
    assert resp.status_code == 201
    joined = " ".join(r.getMessage() for r in caplog.records)
    assert "SecretMedXYZ" not in joined
    assert "500mg" not in joined

    # Migration / model contract (no live DB required).
    from pathlib import Path

    mig = Path(__file__).resolve().parents[1] / "alembic/versions/018_add_medication_dose_events.py"
    text = mig.read_text()
    assert 'revision = "018"' in text
    assert 'down_revision = "017"' in text
    assert "medication_dose_events" in text
    assert "uq_med_dose_events_schedule_scheduled_for" in text
    assert "ck_med_dose_events_status" in text
    assert "taken" in text and "skipped" in text and "missed" in text
    assert MedicationDoseEvent.__tablename__ == "medication_dose_events"
    assert "uq_med_dose_events_schedule_scheduled_for" in {
        c.name for c in MedicationDoseEvent.__table__.constraints if hasattr(c, "name") and c.name
    }


def test_medhist_create_schema_ignores_client_owner_fields():
    """Client user_id / recorded_at are not part of create schema."""
    fields = MedicationDoseEventCreate.model_fields
    assert "user_id" not in fields
    assert "recorded_at" not in fields
    assert "family_member_id" not in fields
