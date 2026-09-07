"""S6-S5 / HN-RX-004 — link OCR-confirmed prescription to owned family member."""
from __future__ import annotations

import inspect
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import prescriptions as rx
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.medical_record import MedicalRecord
from app.models.prescription import Prescription


def _user(uid: int = 1, allergies=None):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@ex.com",
        is_active=True,
        token_version=0,
        allergies=allergies,
    )


def _member(mid: int, owner_id: int, name: str = "Alex", active: bool = True):
    return SimpleNamespace(
        id=mid,
        user_id=owner_id,
        name=name,
        is_active=active,
        medical_conditions=None,
        allergies=None,
        notes=None,
    )


def _rx_row(
    rid: int = 9,
    owner_id: int = 1,
    family_member_id: int | None = None,
):
    return SimpleNamespace(
        id=rid,
        user_id=owner_id,
        family_member_id=family_member_id,
        medical_record_id=5,
        doctor_name="Lee",
        hospital=None,
        prescription_date=None,
        extracted_medicines=json.dumps([{"name": "Paracetamol"}]),
        ai_summary="Saved after user confirmation of OCR extraction.",
        created_at=datetime.now(timezone.utc),
    )


def _result_one(obj):
    result = MagicMock()
    result.scalar_one_or_none.return_value = obj
    result.scalars.return_value.all.return_value = [obj] if obj is not None else []
    return result


MEDS = json.dumps([{"name": "Paracetamol", "dosage": "500mg"}])
FILES = {"file": ("rx.jpg", b"fake-image", "image/jpeg")}


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
def rx_app():
    def _make(user):
        app = FastAPI()
        app.include_router(rx.router, prefix="/api/v1/prescriptions")

        async def _override_user():
            return user

        async def _override_db():
            db = AsyncMock()
            db.add = MagicMock()
            db.flush = AsyncMock()
            db.commit = AsyncMock()
            db.refresh = AsyncMock()
            yield db

        app.dependency_overrides[get_current_user] = _override_user
        app.dependency_overrides[get_db] = _override_db
        return app

    return _make


def _persist_db(*, family_member=None):
    added: list = []

    async def override_db():
        db = AsyncMock()

        def add(obj):
            added.append(obj)
            if isinstance(obj, MedicalRecord) and getattr(obj, "id", None) is None:
                obj.id = 5
            if isinstance(obj, Prescription) and getattr(obj, "id", None) is None:
                obj.id = 9

        db.add = add
        db.flush = AsyncMock()
        db.commit = AsyncMock()

        async def refresh(obj):
            if getattr(obj, "id", None) is None:
                obj.id = 9

        db.refresh = AsyncMock(side_effect=refresh)
        db.execute = AsyncMock(return_value=_result_one(family_member))
        db._added = added
        yield db

    return override_db, added


async def _confirm(client, extra_data=None):
    data = {"medicines_json": MEDS}
    if extra_data:
        data.update(extra_data)
    with patch.object(rx, "save_file", new=AsyncMock(return_value="prescriptions/1/rx.jpg")) as save:
        resp = await client.post(
            "/api/v1/prescriptions/confirm",
            data=data,
            files=FILES,
        )
    return resp, save


@pytest.mark.anyio
async def test_rx_family_sec_01_02_owned_family_confirm(rx_app):
    """RX-FAMILY-SEC-01 / 02 / FUNC-02 / FUNC-03"""
    user = _user(1)
    app = rx_app(user)
    member = _member(10, 1, name="Alex")
    override, added = _persist_db(family_member=member)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, save = await _confirm(client, {"family_member_id": "10"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == 9
    assert body["family_member_id"] == 10
    assert body["family_member_name"] == "Alex"
    assert body["user_confirmed"] is True
    save.assert_awaited()
    prescriptions = [o for o in added if isinstance(o, Prescription)]
    assert len(prescriptions) == 1
    assert prescriptions[0].family_member_id == 10
    assert prescriptions[0].user_id == 1


@pytest.mark.anyio
async def test_rx_family_sec_03_func_01_04_self_null_omitted(rx_app):
    """RX-FAMILY-SEC-03 / FUNC-01 / FUNC-04"""
    user = _user(1)
    app = rx_app(user)
    override, added = _persist_db(family_member=None)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, _ = await _confirm(client)
    assert resp.status_code == 200
    body = resp.json()
    assert body["family_member_id"] is None
    assert body.get("family_member_name") is None
    prescriptions = [o for o in added if isinstance(o, Prescription)]
    assert prescriptions[0].family_member_id is None
    assert prescriptions[0].user_id == 1


@pytest.mark.anyio
async def test_rx_family_sec_04_05_cross_user_404_no_row(rx_app):
    """RX-FAMILY-SEC-04 / 05 / FUNC-05"""
    user = _user(1)
    app = rx_app(user)
    override, added = _persist_db(family_member=None)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, save = await _confirm(client, {"family_member_id": "99"})
    assert resp.status_code == 404
    assert resp.json()["detail"] == "Family member not found"
    assert added == []
    save.assert_not_called()


@pytest.mark.anyio
async def test_rx_family_sec_06_unauthenticated_rejected():
    """RX-FAMILY-SEC-06"""
    app = FastAPI()
    app.include_router(rx.router, prefix="/api/v1/prescriptions")

    async def _db():
        db = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = _db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/prescriptions/confirm",
            data={"medicines_json": MEDS},
            files=FILES,
        )
    assert resp.status_code in (401, 403, 422)


@pytest.mark.anyio
async def test_rx_family_sec_07_nonexistent_family_404(rx_app):
    """RX-FAMILY-SEC-07"""
    user = _user(1)
    app = rx_app(user)
    override, added = _persist_db(family_member=None)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, save = await _confirm(client, {"family_member_id": "40404"})
    assert resp.status_code == 404
    assert resp.json()["detail"] == "Family member not found"
    assert added == []
    save.assert_not_called()


@pytest.mark.anyio
async def test_rx_family_sec_08_owner_get_protection(rx_app):
    """RX-FAMILY-SEC-08"""
    other = _user(2)
    app = rx_app(other)

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(return_value=_result_one(None))
        yield db

    app.dependency_overrides[get_db] = override_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.get("/api/v1/prescriptions/9")
    assert resp.status_code == 404
    assert resp.json()["detail"] == "Prescription not found"


@pytest.mark.anyio
async def test_rx_family_sec_09_func_06_ocr_confirm_gate(rx_app):
    """RX-FAMILY-SEC-09 / FUNC-06"""
    user = _user(1)
    app = rx_app(user)
    override, added = _persist_db()
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        with patch.object(rx, "save_file", new=AsyncMock(return_value="x")) as save_empty:
            empty = await client.post(
                "/api/v1/prescriptions/confirm",
                data={"medicines_json": "[]"},
                files=FILES,
            )
        persist = await client.post(
            "/api/v1/prescriptions/scan",
            data={"persist": "true", "family_member_id": "10"},
            files=FILES,
        )
    assert empty.status_code == 400
    save_empty.assert_not_called()
    assert added == []
    assert persist.status_code == 400
    assert "disabled" in persist.json()["detail"].lower()


@pytest.mark.anyio
async def test_rx_family_sec_10_scan_persist_cannot_bypass_ownership(rx_app):
    """RX-FAMILY-SEC-10 — legacy persist path stays disabled (no unowned write)."""
    user = _user(1)
    app = rx_app(user)
    override, added = _persist_db(family_member=None)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        with patch.object(rx, "save_file", new=AsyncMock(return_value="x")) as save:
            resp = await client.post(
                "/api/v1/prescriptions/scan",
                data={"persist": "true", "family_member_id": "99"},
                files=FILES,
            )
    assert resp.status_code == 400
    assert added == []
    save.assert_not_called()


@pytest.mark.anyio
async def test_rx_family_sec_11_client_cannot_override_owner(rx_app):
    """RX-FAMILY-SEC-11"""
    user = _user(1)
    app = rx_app(user)
    member = _member(10, 1)
    override, added = _persist_db(family_member=member)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, _ = await _confirm(
            client,
            {
                "family_member_id": "10",
                "user_id": "2",
                "owner_id": "2",
            },
        )
    assert resp.status_code == 200
    prescriptions = [o for o in added if isinstance(o, Prescription)]
    records = [o for o in added if isinstance(o, MedicalRecord)]
    assert prescriptions[0].user_id == 1
    assert records[0].user_id == 1
    assert prescriptions[0].family_member_id == 10


def test_rx_family_sec_12_no_clinical_payload_in_logs():
    """RX-FAMILY-SEC-12"""
    src = Path(rx.__file__).read_text(encoding="utf-8")
    assert "prescription_confirmed" in src
    assert "raw_ocr_text" in src  # persisted, not a log argument
    # Audit extras are identifiers only
    confirm_block = src.split("prescription_confirmed", 1)[1].split("return {", 1)[0]
    assert "user_id" in confirm_block
    assert "prescription_id" in confirm_block
    assert "family_member_id" in confirm_block
    assert "allergies" not in confirm_block
    assert "medical_conditions" not in confirm_block
    assert "notes" not in confirm_block
    assert "extracted_medicines" not in confirm_block
    assert "raw_ocr_text" not in confirm_block
    assert "ENCRYPTION_KEY" not in src
    assert inspect.signature(rx.confirm_prescription).parameters["family_member_id"]


@pytest.mark.anyio
async def test_rx_family_inactive_member_404(rx_app):
    user = _user(1)
    app = rx_app(user)
    # Query filters is_active=True, so inactive looks like missing.
    override, added = _persist_db(family_member=None)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, save = await _confirm(client, {"family_member_id": "10"})
    assert resp.status_code == 404
    assert added == []
    save.assert_not_called()
