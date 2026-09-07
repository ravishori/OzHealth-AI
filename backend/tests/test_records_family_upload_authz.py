"""S6-S6 / HN-FAMILY-011 residual — records upload family_member_id ownership."""
from __future__ import annotations

import inspect
import os
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import records as records_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.medical_record import MedicalRecord
from app.utils import storage as storage_mod


def _user(uid: int = 1):
    return SimpleNamespace(id=uid, email=f"u{uid}@ex.com", is_active=True, token_version=0)


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


def _result_one(obj):
    result = MagicMock()
    result.scalar_one_or_none.return_value = obj
    result.scalars.return_value.all.return_value = [obj] if obj is not None else []
    return result


FILES = {"file": ("labs.pdf", b"%PDF-1.4 synth", "application/pdf")}
DATA = {"record_type": "lab_report", "title": "Labs"}


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
def rec_app():
    def _make(user):
        app = FastAPI()
        app.include_router(records_route.router, prefix="/api/v1/records")

        async def _override_user():
            return user

        async def _override_db():
            db = AsyncMock()
            db.add = MagicMock()
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
                obj.id = 101
                obj.created_at = None

        db.add = add
        db.commit = AsyncMock()

        async def refresh(obj):
            if getattr(obj, "id", None) is None:
                obj.id = 101

        db.refresh = AsyncMock(side_effect=refresh)
        db.execute = AsyncMock(return_value=_result_one(family_member))
        yield db

    return override_db, added


async def _upload(client, extra_data=None):
    data = dict(DATA)
    if extra_data:
        data.update(extra_data)
    with patch.object(
        records_route,
        "save_encrypted_medical_file",
        new=AsyncMock(return_value="records/1/labs.pdf"),
    ) as save:
        resp = await client.post(
            "/api/v1/records/upload",
            data=data,
            files=FILES,
        )
    return resp, save


@pytest.mark.anyio
async def test_record_family_sec_01_owned_active_upload(rec_app):
    """RECORD-FAMILY-SEC-01"""
    user = _user(1)
    app = rec_app(user)
    member = _member(10, 1, name="Alex")
    override, added = _persist_db(family_member=member)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, save = await _upload(client, {"family_member_id": "10"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["family_member_id"] == 10
    assert body["user_id"] == 1
    save.assert_awaited()
    records = [o for o in added if isinstance(o, MedicalRecord)]
    assert len(records) == 1
    assert records[0].family_member_id == 10
    assert records[0].user_id == 1


@pytest.mark.anyio
async def test_record_family_sec_02_omitted_family_id_self(rec_app):
    """RECORD-FAMILY-SEC-02"""
    user = _user(1)
    app = rec_app(user)
    override, added = _persist_db(family_member=None)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, save = await _upload(client)
    assert resp.status_code == 200
    assert resp.json()["family_member_id"] is None
    save.assert_awaited()
    records = [o for o in added if isinstance(o, MedicalRecord)]
    assert records[0].family_member_id is None
    assert records[0].user_id == 1


@pytest.mark.anyio
async def test_record_family_sec_03_08_cross_user_404_no_write(rec_app):
    """RECORD-FAMILY-SEC-03 / RECORD-FAMILY-SEC-08"""
    user = _user(1)
    app = rec_app(user)
    override, added = _persist_db(family_member=None)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, save = await _upload(client, {"family_member_id": "99"})
    assert resp.status_code == 404
    assert resp.json()["detail"] == "Family member not found"
    assert added == []
    save.assert_not_called()


@pytest.mark.anyio
async def test_record_family_sec_04_nonexistent_404_no_write(rec_app):
    """RECORD-FAMILY-SEC-04"""
    user = _user(1)
    app = rec_app(user)
    override, added = _persist_db(family_member=None)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, save = await _upload(client, {"family_member_id": "40404"})
    assert resp.status_code == 404
    assert resp.json()["detail"] == "Family member not found"
    assert added == []
    save.assert_not_called()


@pytest.mark.anyio
async def test_record_family_sec_05_inactive_404_no_write(rec_app):
    """RECORD-FAMILY-SEC-05 — query requires is_active=True, so inactive is missing."""
    user = _user(1)
    app = rec_app(user)
    override, added = _persist_db(family_member=None)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, save = await _upload(client, {"family_member_id": "10"})
    assert resp.status_code == 404
    assert added == []
    save.assert_not_called()


@pytest.mark.anyio
async def test_record_family_sec_06_unauthenticated_rejected():
    """RECORD-FAMILY-SEC-06"""
    app = FastAPI()
    app.include_router(records_route.router, prefix="/api/v1/records")

    async def _db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = _db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/records/upload",
            data=DATA,
            files=FILES,
        )
    assert resp.status_code in (401, 403, 422)


@pytest.mark.anyio
async def test_record_family_sec_07_client_cannot_override_owner(rec_app):
    """RECORD-FAMILY-SEC-07"""
    user = _user(1)
    app = rec_app(user)
    member = _member(10, 1)
    override, added = _persist_db(family_member=member)
    app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp, _ = await _upload(
            client,
            {
                "family_member_id": "10",
                "user_id": "2",
                "owner_id": "2",
            },
        )
    assert resp.status_code == 200
    records = [o for o in added if isinstance(o, MedicalRecord)]
    assert records[0].user_id == 1
    assert records[0].family_member_id == 10
    assert resp.json()["user_id"] == 1


@pytest.mark.anyio
async def test_record_family_sec_09_owner_acl_intact(rec_app):
    """RECORD-FAMILY-SEC-09"""
    other = _user(2)
    app = rec_app(other)

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(return_value=_result_one(None))
        yield db

    app.dependency_overrides[get_db] = override_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        meta = await client.get("/api/v1/records/10")
        file_r = await client.get("/api/v1/records/10/file")
        delete_r = await client.delete("/api/v1/records/10")
    assert meta.status_code == 404
    assert file_r.status_code == 404
    assert delete_r.status_code == 404
    assert meta.json()["detail"] == "Record not found"


def test_record_family_sec_10_encryption_path_unchanged():
    """RECORD-FAMILY-SEC-10 — upload still uses encrypted storage after ownership check."""
    src = Path(records_route.__file__).read_text(encoding="utf-8")
    helper_src = inspect.getsource(records_route.upload_record)
    assert "save_encrypted_medical_file" in helper_src
    assert "_require_owned_active_family_member" in helper_src
    # Ownership runs before encrypted write.
    authz_idx = helper_src.find("_require_owned_active_family_member")
    save_idx = helper_src.find("save_encrypted_medical_file")
    assert 0 <= authz_idx < save_idx
    assert "read_medical_record_bytes" in src
    assert inspect.signature(records_route.upload_record).parameters["family_member_id"]


def test_record_family_sec_audit_identifiers_only():
    src = Path(records_route.__file__).read_text(encoding="utf-8")
    block = src.split("medical_record_uploaded", 1)[1].split("return _to_dict", 1)[0]
    assert "user_id" in block
    assert "record_id" in block
    assert "family_member_id" in block
    assert "notes" not in block
    assert "file_url" not in block
    assert "allergies" not in src.split("async def upload_record")[1].split("async def get_record")[0]
    assert "ENCRYPTION_KEY" not in src
    assert storage_mod.save_encrypted_medical_file is not None
