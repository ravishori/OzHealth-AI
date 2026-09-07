"""HN-HEALTH-005 — edit health metric API contracts."""
from __future__ import annotations

from datetime import datetime, timezone, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from app.api.routes import health_metrics as hm_route
from app.core.deps import get_current_user
from app.core.database import get_db
from app.schemas.health_metric import HealthMetricUpdate


def _user(uid: int = 1):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@ex.com",
        is_active=True,
        token_version=0,
    )


def _metric(
    mid: int = 10,
    owner_id: int = 1,
    *,
    metric_type: str = "heart_rate",
    value: float = 72.0,
    value2: float | None = None,
    unit: str | None = "bpm",
    notes: str | None = "resting",
    family_member_id: int | None = None,
    recorded_at: datetime | None = None,
):
    return SimpleNamespace(
        id=mid,
        user_id=owner_id,
        family_member_id=family_member_id,
        metric_type=metric_type,
        value=value,
        value2=value2,
        unit=unit,
        notes=notes,
        recorded_at=recorded_at or datetime.now(timezone.utc),
        created_at=datetime.now(timezone.utc),
    )


def _member(mid: int, owner_id: int, name: str = "Alex", active: bool = True):
    return SimpleNamespace(
        id=mid,
        user_id=owner_id,
        name=name,
        is_active=active,
    )


def _hm_app(user=None):
    app = FastAPI()
    app.include_router(hm_route.router, prefix="/api/v1/health-metrics")

    async def _override_db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = _override_db
    if user is not None:

        async def _override_user():
            return user

        app.dependency_overrides[get_current_user] = _override_user
    return app


def _db_with_metric(metric):
    db = AsyncMock()
    db.commit = AsyncMock()
    db.refresh = AsyncMock()

    async def _execute(stmt):
        result = MagicMock()
        # Ownership-scoped get returns the metric only when caller wired it.
        result.scalar_one_or_none = MagicMock(return_value=metric)
        result.scalars = MagicMock(
            return_value=MagicMock(all=MagicMock(return_value=[metric] if metric else []))
        )
        return result

    db.execute = AsyncMock(side_effect=_execute)
    return db


# ── HEALTH-005-01 / 05 / 15 ───────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_005_01_05_15_owner_update_persists_no_duplicate():
    """Owner can update; value persists; does not create a second row."""
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(10, 1, value=72.0)
    db = _db_with_metric(metric)
    added: list = []
    db.add = MagicMock(side_effect=lambda o: added.append(o))

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(hm_route.CacheService, "delete", new_callable=AsyncMock) as cache_del:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/health-metrics/10",
                json={"value": 80.0},
            )

    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == 10
    assert body["user_id"] == 1
    assert body["value"] == 80.0
    assert metric.value == 80.0
    assert added == []  # update in place — no duplicate
    assert db.commit.await_count == 1
    cache_del.assert_awaited()


# ── HEALTH-005-02 ─────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_005_02_unauthenticated_rejected():
    app = _hm_app(user=None)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.put("/api/v1/health-metrics/10", json={"value": 80.0})
    assert resp.status_code in (401, 403)


# ── HEALTH-005-03 / 04 ────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_005_03_04_cross_user_and_missing_are_404():
    user = _user(1)
    app = _hm_app(user)
    db = AsyncMock()
    db.commit = AsyncMock()

    async def _execute(_stmt):
        result = MagicMock()
        result.scalar_one_or_none = MagicMock(return_value=None)
        return result

    db.execute = AsyncMock(side_effect=_execute)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.put("/api/v1/health-metrics/999", json={"value": 80.0})
    assert resp.status_code == 404
    assert "not found" in resp.json()["detail"].lower()


# ── HEALTH-005-06 / 07 / 08 / 09 ───────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_005_06_07_08_09_value2_unit_notes_recorded_at():
    user = _user(1)
    app = _hm_app(user)
    recorded = datetime(2026, 1, 15, 10, 0, tzinfo=timezone.utc)
    metric = _metric(
        11,
        1,
        metric_type="blood_pressure",
        value=120.0,
        value2=80.0,
        unit="mmHg",
        notes="old",
        recorded_at=recorded,
    )
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    new_ts = (recorded + timedelta(hours=2)).isoformat()
    with patch.object(hm_route.CacheService, "delete", new_callable=AsyncMock):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/health-metrics/11",
                json={
                    "value": 118.0,
                    "value2": 76.0,
                    "unit": "mmHg",
                    "notes": "after walk",
                    "recorded_at": new_ts,
                },
            )

    assert resp.status_code == 200
    body = resp.json()
    assert body["value"] == 118.0
    assert body["value2"] == 76.0
    assert body["unit"] == "mmHg"
    assert body["notes"] == "after walk"
    assert metric.value2 == 76.0
    assert metric.notes == "after walk"
    assert metric.recorded_at is not None


# ── HEALTH-005-10 ─────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_005_10_invalid_input_rejected():
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(12, 1)
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp_nan = await client.put(
            "/api/v1/health-metrics/12",
            json={"value": "not-a-number"},
        )
        resp_empty = await client.put("/api/v1/health-metrics/12", json={})

    assert resp_nan.status_code == 422
    assert resp_empty.status_code == 422


def test_health_005_10_schema_rejects_non_finite():
    with pytest.raises(ValidationError):
        HealthMetricUpdate(value=float("inf"))


# ── HEALTH-005-11 ─────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_005_11_client_cannot_change_user_id():
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(13, 1, value=70.0)
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(hm_route.CacheService, "delete", new_callable=AsyncMock):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/health-metrics/13",
                json={"value": 71.0, "user_id": 999, "id": 1},
            )

    assert resp.status_code == 200
    assert metric.user_id == 1
    assert resp.json()["user_id"] == 1
    assert resp.json()["id"] == 13


# ── HEALTH-005-12 / 13 ────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_005_12_owned_family_member_allowed():
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(14, 1, family_member_id=None)
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(
        hm_route,
        "_require_owned_active_family_member",
        new_callable=AsyncMock,
        return_value=_member(5, 1),
    ) as req, patch.object(
        hm_route.CacheService, "delete", new_callable=AsyncMock
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/health-metrics/14",
                json={"family_member_id": 5},
            )
        req.assert_awaited()

    assert resp.status_code == 200
    assert metric.family_member_id == 5


@pytest.mark.anyio
async def test_health_005_13_unowned_or_inactive_family_rejected():
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(15, 1)
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    async def _deny(*_a, **_k):
        raise HTTPException(status_code=404, detail="Family member not found")

    with patch.object(
        hm_route,
        "_require_owned_active_family_member",
        new_callable=AsyncMock,
        side_effect=_deny,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/health-metrics/15",
                json={"family_member_id": 99},
            )

    assert resp.status_code == 404


@pytest.mark.anyio
async def test_health_005_13_helper_rejects_inactive_member():
    db = AsyncMock()

    async def _execute(_stmt):
        result = MagicMock()
        result.scalar_one_or_none = MagicMock(return_value=None)
        return result

    db.execute = AsyncMock(side_effect=_execute)
    with pytest.raises(HTTPException) as ei:
        await hm_route._require_owned_active_family_member(db, 7, 1)
    assert ei.value.status_code == 404


# ── HEALTH-005-14 ─────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_005_14_summary_reflects_updated_value():
    """After update, summary rebuild uses new value (cache invalidated)."""
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(16, 1, metric_type="heart_rate", value=90.0, unit="bpm")
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    deleted_keys: list[str] = []

    async def _cache_delete(key):
        deleted_keys.append(key)

    with patch.object(
        hm_route.CacheService, "delete", new_callable=AsyncMock, side_effect=_cache_delete
    ), patch.object(
        hm_route.CacheService, "get", new_callable=AsyncMock, return_value=None
    ), patch.object(
        hm_route.CacheService, "set", new_callable=AsyncMock
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            put = await client.put(
                "/api/v1/health-metrics/16",
                json={"value": 65.0},
            )
            assert put.status_code == 200
            assert metric.value == 65.0
            assert any(k.startswith("metrics:summary:1") for k in deleted_keys)

            summary = await client.get("/api/v1/health-metrics/summary")

    assert summary.status_code == 200
    body = summary.json()
    assert "heart_rate" in body
    assert body["heart_rate"]["latest_value"] == 65.0
    assert body["heart_rate"]["status"] == hm_route._compute_status(
        "heart_rate", 65.0, None
    )
    # History entries include id for edit UX
    assert body["heart_rate"]["history"][0]["id"] == 16


# ── Ownership helper unit ─────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_005_get_owned_metric_scopes_by_user():
    db = AsyncMock()

    async def _execute(_stmt):
        result = MagicMock()
        result.scalar_one_or_none = MagicMock(return_value=None)
        return result

    db.execute = AsyncMock(side_effect=_execute)
    with pytest.raises(HTTPException) as ei:
        await hm_route._get_owned_metric(db, 1, 2)
    assert ei.value.status_code == 404
