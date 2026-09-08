"""HN-HEALTH-005 — edit health metric (HEALTH5-01 .. HEALTH5-23)."""
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
    created_at: datetime | None = None,
):
    created = created_at or datetime(2026, 1, 1, 8, 0, tzinfo=timezone.utc)
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
        created_at=created,
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
        result.scalar_one_or_none = MagicMock(return_value=metric)
        result.scalars = MagicMock(
            return_value=MagicMock(all=MagicMock(return_value=[metric] if metric else []))
        )
        return result

    db.execute = AsyncMock(side_effect=_execute)
    return db


# ── HEALTH5-01 ────────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health5_01_authenticated_owner_can_update():
    """HEALTH5-01 — Authenticated owner can update own metric."""
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(10, 1, value=72.0)
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(hm_route.CacheService, "delete", new_callable=AsyncMock):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put("/api/v1/health-metrics/10", json={"value": 80.0})

    assert resp.status_code == 200
    assert resp.json()["value"] == 80.0
    assert metric.value == 80.0


# ── HEALTH5-02 ────────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health5_02_unauthenticated_update_rejected():
    """HEALTH5-02 — Unauthenticated update is rejected."""
    app = _hm_app(user=None)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.put("/api/v1/health-metrics/10", json={"value": 80.0})
    assert resp.status_code in (401, 403)


# ── HEALTH5-03 / HEALTH5-08 ───────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health5_03_08_cross_user_metric_update_rejected_no_leak():
    """HEALTH5-03 / HEALTH5-08 — Cross-user update rejected; no existence leak."""
    user = _user(1)
    app = _hm_app(user)
    db = AsyncMock()
    db.commit = AsyncMock()

    async def _execute(_stmt):
        result = MagicMock()
        # Owner-scoped query returns none for another user's id.
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
    detail = resp.json()["detail"].lower()
    assert "not found" in detail
    assert "user" not in detail
    assert "owner" not in detail


# ── HEALTH5-04 / HEALTH5-05 ───────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health5_04_05_client_user_id_ignored_ownership_unchanged():
    """HEALTH5-04 / HEALTH5-05 — Client user_id ignored; ownership unchanged."""
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(13, 1, value=70.0, family_member_id=3)
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
    assert metric.family_member_id == 3
    assert resp.json()["user_id"] == 1
    assert resp.json()["id"] == 13


# ── HEALTH5-06 / HEALTH5-07 ───────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health5_06_07_family_member_reassignment_ignored():
    """HEALTH5-06 / HEALTH5-07 — Unowned/inactive FM cannot be assigned; frozen."""
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(14, 1, family_member_id=5)
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(hm_route.CacheService, "delete", new_callable=AsyncMock):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/health-metrics/14",
                json={"value": 75.0, "family_member_id": 99},
            )

    assert resp.status_code == 200
    # family_member_id not in update schema — ignored; ownership preserved.
    assert metric.family_member_id == 5
    assert "family_member_id" not in HealthMetricUpdate.model_fields


@pytest.mark.anyio
async def test_health5_07_helper_still_rejects_inactive_member():
    """Inactive/unowned family helper remains fail-closed for create paths."""
    db = AsyncMock()

    async def _execute(_stmt):
        result = MagicMock()
        result.scalar_one_or_none = MagicMock(return_value=None)
        return result

    db.execute = AsyncMock(side_effect=_execute)
    with pytest.raises(HTTPException) as ei:
        await hm_route._require_owned_active_family_member(db, 7, 1)
    assert ei.value.status_code == 404


# ── HEALTH5-09 .. HEALTH5-13 ──────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health5_09_13_editable_fields_update():
    """HEALTH5-09..13 — value, value2, unit, notes, recorded_at updatable."""
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
    assert body["value"] == 118.0  # HEALTH5-09
    assert body["value2"] == 76.0  # HEALTH5-10
    assert body["unit"] == "mmHg"  # HEALTH5-11
    assert body["notes"] == "after walk"  # HEALTH5-12
    assert metric.recorded_at is not None  # HEALTH5-13
    assert metric.value2 == 76.0


# ── HEALTH5-14 / HEALTH5-15 ───────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health5_14_invalid_value_rejected():
    """HEALTH5-14 — Invalid value rejected per existing validation."""
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

    with pytest.raises(ValidationError):
        HealthMetricUpdate(value=float("inf"))


@pytest.mark.anyio
async def test_health5_15_malformed_timestamp_rejected():
    """HEALTH5-15 — Malformed timestamp is rejected."""
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(17, 1)
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.put(
            "/api/v1/health-metrics/17",
            json={"recorded_at": "not-a-timestamp"},
        )
        resp_null = await client.put(
            "/api/v1/health-metrics/17",
            json={"recorded_at": None},
        )

    assert resp.status_code == 422
    assert resp_null.status_code == 422


# ── HEALTH5-16 / HEALTH5-17 / HEALTH5-18 ──────────────────────────────────────


@pytest.mark.anyio
async def test_health5_16_17_18_identity_created_no_duplicate():
    """HEALTH5-16..18 — id/created_at unchanged; update in place (no duplicate)."""
    user = _user(1)
    app = _hm_app(user)
    created = datetime(2026, 1, 1, 8, 0, tzinfo=timezone.utc)
    metric = _metric(10, 1, value=72.0, created_at=created)
    db = _db_with_metric(metric)
    added: list = []
    db.add = MagicMock(side_effect=lambda o: added.append(o))

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(hm_route.CacheService, "delete", new_callable=AsyncMock):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/health-metrics/10",
                json={"value": 80.0, "metric_type": "weight", "created_at": "2099-01-01T00:00:00Z"},
            )

    assert resp.status_code == 200
    assert resp.json()["id"] == 10  # HEALTH5-16
    assert metric.metric_type == "heart_rate"
    assert metric.created_at == created  # HEALTH5-17
    assert added == []  # HEALTH5-18
    assert db.commit.await_count == 1


# ── HEALTH5-19 .. HEALTH5-23 ──────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health5_19_23_history_summary_trend_cache():
    """HEALTH5-19..23 — history/summary/trend reflect edit; cache invalidated."""
    user = _user(1)
    app = _hm_app(user)
    older = _metric(
        15,
        1,
        metric_type="heart_rate",
        value=90.0,
        unit="bpm",
        recorded_at=datetime(2026, 1, 10, tzinfo=timezone.utc),
    )
    latest = _metric(
        16,
        1,
        metric_type="heart_rate",
        value=90.0,
        unit="bpm",
        recorded_at=datetime(2026, 1, 20, tzinfo=timezone.utc),
    )
    db = AsyncMock()
    db.commit = AsyncMock()
    db.refresh = AsyncMock()
    added: list = []
    db.add = MagicMock(side_effect=lambda o: added.append(o))

    call_count = {"n": 0}

    async def _execute(_stmt):
        result = MagicMock()
        call_count["n"] += 1
        # First call: owned metric lookup for PUT; later: summary list.
        if call_count["n"] == 1:
            result.scalar_one_or_none = MagicMock(return_value=latest)
            result.scalars = MagicMock(
                return_value=MagicMock(all=MagicMock(return_value=[latest]))
            )
        else:
            # After edit, latest is 65 and older remains 90 → trend down.
            result.scalar_one_or_none = MagicMock(return_value=latest)
            result.scalars = MagicMock(
                return_value=MagicMock(all=MagicMock(return_value=[latest, older]))
            )
        return result

    db.execute = AsyncMock(side_effect=_execute)

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
            assert latest.value == 65.0
            assert any(k.startswith("metrics:summary:1") for k in deleted_keys)  # HEALTH5-23

            # List history (HEALTH5-19)
            hist = await client.get("/api/v1/health-metrics/?metric_type=heart_rate")
            summary = await client.get("/api/v1/health-metrics/summary")

    assert hist.status_code == 200
    hist_body = hist.json()
    assert any(r.get("value") == 65.0 or r.get("id") == 16 for r in hist_body)

    assert summary.status_code == 200
    body = summary.json()
    assert "heart_rate" in body
    assert body["heart_rate"]["latest_value"] == 65.0  # HEALTH5-20
    assert body["heart_rate"]["latest_value"] != 90.0  # HEALTH5-22
    assert body["heart_rate"]["trend"] == "down"  # HEALTH5-21
    assert body["heart_rate"]["history"][0]["id"] == 16
    assert body["heart_rate"]["history"][0]["value"] == 65.0
    assert added == []


# ── Ownership helper unit ─────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health5_get_owned_metric_scopes_by_user():
    db = AsyncMock()

    async def _execute(_stmt):
        result = MagicMock()
        result.scalar_one_or_none = MagicMock(return_value=None)
        return result

    db.execute = AsyncMock(side_effect=_execute)
    with pytest.raises(HTTPException) as ei:
        await hm_route._get_owned_metric(db, 1, 2)
    assert ei.value.status_code == 404
