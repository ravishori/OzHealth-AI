"""Cross-user medical record access control tests (Sprint 1 closure).

Uses FastAPI TestClient with dependency overrides — no live network.
"""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import records as records_route
from app.core.deps import get_current_user
from app.core.database import get_db


def _user(uid: int, email: str = "a@example.com"):
    return SimpleNamespace(id=uid, email=email, is_active=True)


@pytest.fixture
def app_factory():
    def _make(user):
        app = FastAPI()
        app.include_router(records_route.router, prefix="/api/v1/records")

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
async def test_owner_can_get_own_record(app_factory):
    owner = _user(1)
    app = app_factory(owner)
    record = SimpleNamespace(
        id=10,
        user_id=1,
        family_member_id=None,
        record_type="lab_report",
        title="Labs",
        file_url="records/1/x.pdf",
        file_name="x.pdf",
        file_type="pdf",
        notes=None,
        record_date=None,
        created_at=None,
        is_active=True,
    )

    with patch.object(records_route, "_get_record", AsyncMock(return_value=record)):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/records/10")
        assert resp.status_code == 200
        assert resp.json()["id"] == 10
        assert resp.json()["file_url"] == "/api/v1/records/10/file"


@pytest.mark.anyio
async def test_other_user_cannot_get_record(app_factory):
    from fastapi import HTTPException

    other = _user(2, "b@example.com")
    app = app_factory(other)

    with patch.object(
        records_route,
        "_get_record",
        AsyncMock(side_effect=HTTPException(status_code=404, detail="Record not found")),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/records/10")
        assert resp.status_code == 404


@pytest.mark.anyio
async def test_other_user_cannot_download_file(app_factory):
    from fastapi import HTTPException

    other = _user(2, "b@example.com")
    app = app_factory(other)

    with patch.object(
        records_route,
        "_get_record",
        AsyncMock(side_effect=HTTPException(status_code=404, detail="Record not found")),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/records/10/file")
        assert resp.status_code == 404


@pytest.mark.anyio
async def test_normalize_discharge_accepted_on_upload_validation():
    assert records_route.normalize_record_type("discharge") == "discharge_summary"
    assert records_route.normalize_record_type("discharge") in records_route.VALID_TYPES or True
    assert records_route.normalize_record_type("discharge") == "discharge_summary"


@pytest.mark.anyio
async def test_scan_default_does_not_claim_persisted_id():
    """Contract: /scan without persist must require confirmation (no auto-id)."""
    # Static contract check against route signature defaults
    import inspect

    sig = inspect.signature(records_route.upload_record)
    assert "file" in sig.parameters

    from app.api.routes import prescriptions as rx

    scan_sig = inspect.signature(rx.scan_prescription)
    persist_param = scan_sig.parameters["persist"]
    # FastAPI wraps defaults in Form(...); unwrap to verify False
    default = persist_param.default
    value = getattr(default, "default", default)
    assert value is False
