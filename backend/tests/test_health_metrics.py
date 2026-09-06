"""S6-S1 / HN-HEALTH-001 / HN-HEALTH-004 — health metrics API."""
from __future__ import annotations

import inspect
import os
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from app.api.routes import health_metrics as hm_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.schemas.health_metric import ALLOWED_METRIC_TYPES, HealthMetricCreate


def _user(uid: int = 1):
    return SimpleNamespace(id=uid, email=f"u{uid}@ex.com", is_active=True, token_version=0)


def _metric(
    mid: int = 1,
    user_id: int = 1,
    metric_type: str = "heart_rate",
    value: float = 72,
    value2: float | None = None,
    unit: str = "bpm",
    notes: str | None = None,
    family_member_id: int | None = None,
    recorded_at: datetime | None = None,
):
    return SimpleNamespace(
        id=mid,
        user_id=user_id,
        family_member_id=family_member_id,
        metric_type=metric_type,
        value=value,
        value2=value2,
        unit=unit,
        notes=notes,
        recorded_at=recorded_at or datetime.now(timezone.utc),
        created_at=datetime.now(timezone.utc),
    )


def _result_all(rows):
    result = MagicMock()
    result.scalars.return_value.all.return_value = rows
    result.scalar_one_or_none.return_value = None
    return result


@pytest.fixture
def hm_app():
    def _make(user):
        app = FastAPI()
        app.include_router(hm_route.router, prefix="/api/v1/health-metrics")

        async def _override_user():
            return user

        async def _override_db():
            db = AsyncMock()
            db.add = MagicMock()
            db.commit = AsyncMock()
            yield db

        app.dependency_overrides[get_current_user] = _override_user
        app.dependency_overrides[get_db] = _override_db
        return app

    return _make


def _create_db_override(refresh_obj_id: int = 101):
    async def override_db():
        db = AsyncMock()
        db.add = MagicMock()
        db.commit = AsyncMock()

        async def refresh(obj):
            obj.id = refresh_obj_id
            if getattr(obj, "recorded_at", None) is None:
                obj.recorded_at = datetime.now(timezone.utc)

        db.refresh = AsyncMock(side_effect=refresh)
        db.execute = AsyncMock(return_value=_result_all([]))
        yield db

    return override_db


@pytest.mark.anyio
async def test_health_be_01_create_valid_metric(hm_app):
    user = _user(1)
    app = hm_app(user)
    app.dependency_overrides[get_db] = _create_db_override(101)
    transport = ASGITransport(app=app)
    with patch.object(hm_route.CacheService, "delete", AsyncMock()), patch.object(
        hm_route.CacheService, "invalidate_prefix", AsyncMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/health-metrics/",
                json={"metric_type": "heart_rate", "value": 72, "unit": "bpm"},
            )
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == 101
    assert body["user_id"] == 1
    assert body["metric_type"] == "heart_rate"
    assert body["value"] == 72
    assert body["unit"] == "bpm"
    assert body["family_member_id"] is None


@pytest.mark.anyio
async def test_health_be_02_reject_missing_metric_type(hm_app):
    app = hm_app(_user(1))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/health-metrics/",
            json={"value": 72},
        )
    assert resp.status_code == 422


@pytest.mark.anyio
async def test_health_be_03_reject_invalid_numeric_input(hm_app):
    app = hm_app(_user(1))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/health-metrics/",
            json={"metric_type": "heart_rate", "value": "not-a-number"},
        )
    assert resp.status_code == 422


@pytest.mark.anyio
async def test_health_be_11_reject_empty_and_malformed(hm_app):
    app = hm_app(_user(1))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        empty_type = await client.post(
            "/api/v1/health-metrics/",
            json={"metric_type": "   ", "value": 72},
        )
        unknown = await client.post(
            "/api/v1/health-metrics/",
            json={"metric_type": "hypertension", "value": 72},
        )
        bp_missing_dia = await client.post(
            "/api/v1/health-metrics/",
            json={"metric_type": "blood_pressure", "value": 120},
        )
    assert empty_type.status_code == 422
    assert unknown.status_code == 422
    assert bp_missing_dia.status_code == 422


@pytest.mark.anyio
async def test_health_be_11b_unauthorized_without_user():
    app = FastAPI()
    app.include_router(hm_route.router, prefix="/api/v1/health-metrics")

    async def _db():
        db = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/health-metrics/",
            json={"metric_type": "heart_rate", "value": 72},
        )
        listing = await client.get("/api/v1/health-metrics/")
    assert resp.status_code in (401, 403, 422)
    assert listing.status_code in (401, 403, 422)


@pytest.mark.anyio
async def test_health_be_04_retrieve_owner_metrics(hm_app):
    user = _user(1)
    app = hm_app(user)
    rows = [
        _metric(1, metric_type="heart_rate", value=80),
        _metric(2, metric_type="weight", value=70),
    ]

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(return_value=_result_all(rows))
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/health-metrics/")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 2
    assert {row["metric_type"] for row in body} == {"heart_rate", "weight"}
    assert all(row["user_id"] == 1 for row in body)


@pytest.mark.anyio
async def test_health_be_05_history_is_newest_first(hm_app):
    user = _user(1)
    app = hm_app(user)
    now = datetime.now(timezone.utc)
    rows = [
        _metric(2, value=80, recorded_at=now),
        _metric(1, value=70, recorded_at=now - timedelta(days=2)),
    ]

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(return_value=_result_all(rows))
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/health-metrics/?metric_type=heart_rate")
    assert resp.status_code == 200
    values = [row["value"] for row in resp.json()]
    assert values == [80, 70]


def _stmt_sql(stmt) -> str:
    return str(stmt.compile(compile_kwargs={"literal_binds": True})).lower()


@pytest.mark.anyio
async def test_health_be_06_07_08_day_filters(hm_app):
    user = _user(1)
    app = hm_app(user)
    captured = []

    async def override_db():
        db = AsyncMock()

        async def execute(stmt, *a, **k):
            captured.append(stmt)
            return _result_all([])

        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for days in (7, 30, 90):
            captured.clear()
            resp = await client.get(f"/api/v1/health-metrics/?days={days}")
            assert resp.status_code == 200, resp.text
            sql = _stmt_sql(captured[-1])
            assert "recorded_at" in sql
            assert "health_metrics" in sql


@pytest.mark.anyio
async def test_health_be_09_cross_user_isolation(hm_app):
    owner = _user(1)
    other = _user(2)
    owner_app = hm_app(owner)
    other_app = hm_app(other)
    owner_rows = [_metric(1, user_id=1, value=72)]

    async def owner_db():
        db = AsyncMock()
        db.execute = AsyncMock(return_value=_result_all(owner_rows))
        yield db

    async def other_db():
        db = AsyncMock()
        db.execute = AsyncMock(return_value=_result_all([]))
        yield db

    owner_app.dependency_overrides[get_db] = owner_db
    other_app.dependency_overrides[get_db] = other_db

    async with AsyncClient(
        transport=ASGITransport(app=owner_app), base_url="http://test"
    ) as client:
        mine = await client.get("/api/v1/health-metrics/")
    async with AsyncClient(
        transport=ASGITransport(app=other_app), base_url="http://test"
    ) as client:
        theirs = await client.get("/api/v1/health-metrics/")

    assert mine.status_code == 200
    assert mine.json()[0]["user_id"] == 1
    assert theirs.status_code == 200
    assert theirs.json() == []


@pytest.mark.anyio
async def test_health_be_10_family_member_authorization(hm_app):
    user = _user(1)
    app = hm_app(user)
    transport = ASGITransport(app=app)
    with patch.object(
        hm_route,
        "_require_owned_active_family_member",
        AsyncMock(side_effect=HTTPException(status_code=404, detail="Family member not found")),
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            create = await client.post(
                "/api/v1/health-metrics/",
                json={
                    "metric_type": "heart_rate",
                    "value": 70,
                    "family_member_id": 999,
                },
            )
            listing = await client.get("/api/v1/health-metrics/?family_member_id=999")
    assert create.status_code == 404
    assert listing.status_code == 404


@pytest.mark.anyio
async def test_health_be_10b_owned_family_member_create(hm_app):
    user = _user(1)
    app = hm_app(user)
    app.dependency_overrides[get_db] = _create_db_override(55)
    member = SimpleNamespace(id=10, user_id=1, name="Alex", is_active=True)
    with patch.object(
        hm_route, "_require_owned_active_family_member", AsyncMock(return_value=member)
    ), patch.object(hm_route.CacheService, "delete", AsyncMock()), patch.object(
        hm_route.CacheService, "invalidate_prefix", AsyncMock()
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/health-metrics/",
                json={
                    "metric_type": "blood_pressure",
                    "value": 120,
                    "value2": 80,
                    "family_member_id": 10,
                },
            )
    assert resp.status_code == 200
    assert resp.json()["family_member_id"] == 10
    assert resp.json()["value"] == 120
    assert resp.json()["value2"] == 80


@pytest.mark.anyio
async def test_health_be_12_no_sensitive_logging():
    src = inspect.getsource(hm_route.log_metric)
    assert "audit_log.info" in src
    extra_line = [line for line in src.splitlines() if "extra=" in line]
    assert extra_line
    joined = " ".join(extra_line)
    assert "metric_type" in joined
    assert "user_id" in joined
    assert "notes" not in joined
    assert '"value"' not in joined
    assert "'value'" not in joined


@pytest.mark.anyio
async def test_health_be_13_metric_types_stay_separated(hm_app):
    user = _user(1)
    app = hm_app(user)
    hr_only = [_metric(1, metric_type="heart_rate", value=72)]
    captured = []

    async def override_db():
        db = AsyncMock()

        async def execute(stmt, *a, **k):
            captured.append(_stmt_sql(stmt))
            return _result_all(hr_only)

        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/health-metrics/?metric_type=heart_rate")
    assert resp.status_code == 200
    assert all(row["metric_type"] == "heart_rate" for row in resp.json())
    assert "heart_rate" in captured[-1]


@pytest.mark.anyio
async def test_health_be_14_sparse_history_is_stored_rows_only(hm_app):
    user = _user(1)
    app = hm_app(user)
    now = datetime.now(timezone.utc)
    sparse = [
        _metric(2, value=80, recorded_at=now),
        _metric(1, value=70, recorded_at=now - timedelta(days=40)),
    ]

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(return_value=_result_all(sparse))
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/health-metrics/?days=90")
    body = resp.json()
    assert len(body) == 2
    assert [row["value"] for row in body] == [80, 70]


def test_health_be_days_cutoff_window():
    cutoff = hm_route._days_cutoff(7)
    assert cutoff is not None
    delta = datetime.now(timezone.utc) - cutoff
    assert timedelta(days=6, hours=23) < delta < timedelta(days=7, minutes=1)
    assert hm_route._days_cutoff(None) is None


def test_health_be_create_schema_rejects_future_and_nonfinite():
    with pytest.raises(ValidationError):
        HealthMetricCreate(metric_type="heart_rate", value=float("inf"))
    future = datetime.now(timezone.utc) + timedelta(days=2)
    with pytest.raises(ValidationError):
        HealthMetricCreate(
            metric_type="weight",
            value=70,
            recorded_at=future,
        )
    assert "blood_pressure" in ALLOWED_METRIC_TYPES
    ok = HealthMetricCreate(
        metric_type="blood_pressure", value=118, value2=76
    )
    assert ok.value2 == 76


@pytest.mark.anyio
async def test_health_family_sec_03_list_owned_family_member(hm_app):
    user = _user(1)
    app = hm_app(user)
    rows = [_metric(1, family_member_id=10, value=88)]
    captured = []

    async def override_db():
        db = AsyncMock()

        async def execute(stmt, *a, **k):
            captured.append(stmt)
            return _result_all(rows)

        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db
    member = SimpleNamespace(id=10, user_id=1, name="Alex", is_active=True)
    with patch.object(
        hm_route, "_require_owned_active_family_member", AsyncMock(return_value=member)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/health-metrics/?family_member_id=10")
    assert resp.status_code == 200
    assert resp.json()[0]["family_member_id"] == 10
    sql = _stmt_sql(captured[-1])
    assert "family_member_id = 10" in sql
    assert "user_id = 1" in sql


@pytest.mark.anyio
async def test_health_family_sec_04_owned_summary(hm_app):
    user = _user(1)
    app = hm_app(user)
    now = datetime.now(timezone.utc)
    hr = [
        _metric(
            1,
            family_member_id=10,
            metric_type="heart_rate",
            value=88,
            recorded_at=now,
        )
    ]

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(return_value=_result_all(hr))
        yield db

    app.dependency_overrides[get_db] = override_db
    member = SimpleNamespace(id=10, user_id=1, name="Alex", is_active=True)
    with patch.object(
        hm_route, "_require_owned_active_family_member", AsyncMock(return_value=member)
    ), patch.object(
        hm_route.CacheService, "get", AsyncMock(return_value=None)
    ), patch.object(
        hm_route.CacheService, "set", AsyncMock()
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/health-metrics/summary?family_member_id=10"
            )
    assert resp.status_code == 200
    body = resp.json()
    assert body["heart_rate"]["latest_value"] == 88


@pytest.mark.anyio
async def test_health_family_sec_05_summary_cross_user_404(hm_app):
    user = _user(1)
    app = hm_app(user)
    transport = ASGITransport(app=app)
    with patch.object(
        hm_route,
        "_require_owned_active_family_member",
        AsyncMock(side_effect=HTTPException(status_code=404, detail="Family member not found")),
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/health-metrics/summary?family_member_id=999"
            )
    assert resp.status_code == 404


@pytest.mark.anyio
async def test_health_family_sec_07_unauthenticated_summary_rejected():
    app = FastAPI()
    app.include_router(hm_route.router, prefix="/api/v1/health-metrics")

    async def _db():
        db = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        summary = await client.get("/api/v1/health-metrics/summary")
        listing = await client.get("/api/v1/health-metrics/?family_member_id=1")
    assert summary.status_code in (401, 403, 422)
    assert listing.status_code in (401, 403, 422)


def test_health_family_sec_08_default_list_is_self_only():
    self_sql = _stmt_sql(hm_route._owner_query(1, None))
    fam_sql = _stmt_sql(hm_route._owner_query(1, 10))
    assert "user_id = 1" in self_sql
    assert "family_member_id is null" in self_sql
    assert "family_member_id = 10" in fam_sql
    assert "is null" not in fam_sql


@pytest.mark.anyio
async def test_health_family_sec_08_http_default_list_sql(hm_app):
    user = _user(1)
    app = hm_app(user)
    captured = []

    async def override_db():
        db = AsyncMock()

        async def execute(stmt, *a, **k):
            captured.append(stmt)
            return _result_all([])

        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/health-metrics/")
    assert resp.status_code == 200
    sql = _stmt_sql(captured[-1])
    assert "family_member_id is null" in sql
