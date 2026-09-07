"""HN-HEALTH-006 — delete health metric API contracts."""
from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.api.routes import health_metrics as hm_route
from app.core.deps import get_current_user
from app.core.database import get_db


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
        recorded_at=datetime.now(timezone.utc),
        created_at=datetime.now(timezone.utc),
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
    db.delete = AsyncMock()

    async def _execute(stmt):
        result = MagicMock()
        result.scalar_one_or_none = MagicMock(return_value=metric)
        result.scalars = MagicMock(
            return_value=MagicMock(
                all=MagicMock(return_value=[metric] if metric else [])
            )
        )
        return result

    db.execute = AsyncMock(side_effect=_execute)
    return db


# ── HEALTH-006-01 / 05 ────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_006_01_05_owner_delete_removes_metric():
    """Authenticated owner can delete; hard-delete called; no other rows touched."""
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(10, 1, value=72.0)
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(hm_route.CacheService, "delete", new_callable=AsyncMock) as cache_del:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.delete("/api/v1/health-metrics/10")

    assert resp.status_code == 200
    assert resp.json()["message"] == "Health metric deleted"
    db.delete.assert_awaited_once_with(metric)
    assert db.commit.await_count == 1
    cache_del.assert_awaited()


# ── HEALTH-006-02 ─────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_006_02_unauthenticated_rejected():
    app = _hm_app(user=None)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.delete("/api/v1/health-metrics/10")
    assert resp.status_code in (401, 403)


# ── HEALTH-006-03 / 04 ────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_006_03_04_cross_user_and_missing_are_404():
    user = _user(1)
    app = _hm_app(user)
    db = AsyncMock()
    db.commit = AsyncMock()
    db.delete = AsyncMock()

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
        resp = await client.delete("/api/v1/health-metrics/999")
    assert resp.status_code == 404
    assert "not found" in resp.json()["detail"].lower()
    db.delete.assert_not_awaited()


# ── HEALTH-006-06 / 07 ────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_006_06_07_summary_cache_invalidated_and_empty_after_delete():
    """Delete invalidates cache; subsequent summary has no heart_rate when gone."""
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(16, 1, metric_type="heart_rate", value=90.0)
    db = _db_with_metric(metric)

    deleted_keys: list[str] = []

    async def _cache_delete(key):
        deleted_keys.append(key)

    # After delete, list/summary queries return empty.
    call_n = {"n": 0}

    async def _execute(_stmt):
        call_n["n"] += 1
        result = MagicMock()
        # First call: ownership get returns metric; later summary queries empty.
        if call_n["n"] == 1:
            result.scalar_one_or_none = MagicMock(return_value=metric)
            result.scalars = MagicMock(
                return_value=MagicMock(all=MagicMock(return_value=[metric]))
            )
        else:
            result.scalar_one_or_none = MagicMock(return_value=None)
            result.scalars = MagicMock(
                return_value=MagicMock(all=MagicMock(return_value=[]))
            )
        return result

    db.execute = AsyncMock(side_effect=_execute)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(
        hm_route.CacheService, "delete", new_callable=AsyncMock, side_effect=_cache_delete
    ), patch.object(
        hm_route.CacheService, "get", new_callable=AsyncMock, return_value=None
    ), patch.object(
        hm_route.CacheService, "set", new_callable=AsyncMock
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            put = await client.delete("/api/v1/health-metrics/16")
            assert put.status_code == 200
            assert any(k.startswith("metrics:summary:1") for k in deleted_keys)

            summary = await client.get("/api/v1/health-metrics/summary")

    assert summary.status_code == 200
    body = summary.json()
    assert "heart_rate" not in body


# ── HEALTH-006-08 / 09 ────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_006_08_family_scoped_metric_deletes_with_family_cache():
    user = _user(1)
    app = _hm_app(user)
    metric = _metric(20, 1, family_member_id=5)
    db = _db_with_metric(metric)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    deleted_keys: list[str] = []

    async def _cache_delete(key):
        deleted_keys.append(key)

    with patch.object(
        hm_route.CacheService, "delete", new_callable=AsyncMock, side_effect=_cache_delete
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.delete("/api/v1/health-metrics/20")

    assert resp.status_code == 200
    assert "metrics:summary:1" in deleted_keys
    assert "metrics:summary:1:fm5" in deleted_keys


@pytest.mark.anyio
async def test_health_006_09_client_user_id_cannot_bypass_ownership():
    """DELETE has no body — ownership is path+auth only; unowned → 404."""
    user = _user(1)
    app = _hm_app(user)
    db = AsyncMock()
    db.delete = AsyncMock()

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
        # Query/body ownership hints must be ignored; still 404 for unowned id.
        resp = await client.delete(
            "/api/v1/health-metrics/55",
            params={"user_id": 1},
        )
    assert resp.status_code == 404
    db.delete.assert_not_awaited()


# ── HEALTH-006-10 ─────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_health_006_10_delete_targets_only_owned_metric():
    metric = _metric(33, 1)
    other = _metric(34, 1)
    db = AsyncMock()
    deleted: list = []

    async def _delete(obj):
        deleted.append(obj)

    db.delete = AsyncMock(side_effect=_delete)
    db.commit = AsyncMock()

    async def _execute(_stmt):
        result = MagicMock()
        result.scalar_one_or_none = MagicMock(return_value=metric)
        return result

    db.execute = AsyncMock(side_effect=_execute)

    user = _user(1)
    app = _hm_app(user)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(hm_route.CacheService, "delete", new_callable=AsyncMock):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.delete("/api/v1/health-metrics/33")

    assert resp.status_code == 200
    assert deleted == [metric]
    assert other not in deleted


@pytest.mark.anyio
async def test_health_006_get_owned_metric_scopes_by_user():
    db = AsyncMock()

    async def _execute(_stmt):
        result = MagicMock()
        result.scalar_one_or_none = MagicMock(return_value=None)
        return result

    db.execute = AsyncMock(side_effect=_execute)
    with pytest.raises(HTTPException) as ei:
        await hm_route._get_owned_metric(db, 1, 2)
    assert ei.value.status_code == 404
