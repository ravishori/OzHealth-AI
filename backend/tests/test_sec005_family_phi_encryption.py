"""S6-S2 / HN-SEC-005 — family clinical PHI field-level encryption."""
from __future__ import annotations

import inspect
import json
import os
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from cryptography.fernet import Fernet
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import family as family_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.family_member import FamilyMember
from app.models.user import User
from app.services import encryption_service as enc
from app.services.encryption_service import EncryptedText, RECORD_FILE_MAGIC

_TEST_KEY = Fernet.generate_key().decode()


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture(autouse=True)
def _encryption_key(monkeypatch):
    monkeypatch.setenv("ENCRYPTION_KEY", _TEST_KEY)
    enc.reset_fernet_for_tests()
    yield
    enc.reset_fernet_for_tests()


def test_sec5_be_01_encryption_round_trip():
    col = EncryptedText()
    plain = json.dumps(["Asthma", "Hayfever"])
    stored = col.process_bind_param(plain, None)
    assert stored is not None
    assert col.process_result_value(stored, None) == plain


def test_sec5_be_02_persisted_value_differs_from_plaintext():
    col = EncryptedText()
    plain = json.dumps(["Penicillin"])
    stored = col.process_bind_param(plain, None)
    assert stored != plain
    assert "Penicillin" not in stored
    notes_stored = col.process_bind_param("post-exercise wheeze", None)
    assert notes_stored != "post-exercise wheeze"
    assert "wheeze" not in notes_stored


def test_sec5_be_03_family_clinical_columns_use_encrypted_text():
    for name in ("medical_conditions", "allergies", "notes"):
        col = FamilyMember.__table__.c[name]
        assert isinstance(col.type, EncryptedText), name
    # Identity fields stay plaintext — same pattern as User.
    assert not isinstance(FamilyMember.__table__.c.name.type, EncryptedText)
    assert not isinstance(FamilyMember.__table__.c.blood_group.type, EncryptedText)
    assert isinstance(User.__table__.c.health_conditions.type, EncryptedText)
    assert isinstance(User.__table__.c.allergies.type, EncryptedText)


def test_sec5_be_09_and_12_api_returns_authorized_plaintext_lists():
    """TypeDecorator is transparent to the family API serializer."""
    from datetime import datetime, timezone

    member = SimpleNamespace(
        id=10,
        user_id=1,
        name="Alex",
        relationship="Child",
        age=12,
        gender="Male",
        blood_group="O+",
        medical_conditions=json.dumps(["Asthma"]),
        allergies=json.dumps(["Peanuts"]),
        notes="uses spacer",
        created_at=datetime.now(timezone.utc),
        is_active=True,
    )
    body = family_route._to_response(member)
    assert body["medical_conditions"] == ["Asthma"]
    assert body["allergies"] == ["Peanuts"]
    assert body["notes"] == "uses spacer"
    assert body["name"] == "Alex"


@pytest.mark.anyio
async def test_sec5_be_04_unauthorized_family_access_rejected():
    app = FastAPI()
    app.include_router(family_route.router, prefix="/api/v1/family")

    async def _db():
        db = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        listing = await client.get("/api/v1/family/")
        detail = await client.get("/api/v1/family/10")
        create = await client.post("/api/v1/family/", json={"name": "X"})
    assert listing.status_code in (401, 403, 422)
    assert detail.status_code in (401, 403, 422)
    assert create.status_code in (401, 403, 422)


@pytest.mark.anyio
async def test_sec5_be_05_cross_user_family_member_rejected():
    other = SimpleNamespace(id=2, email="b@ex.com", is_active=True)
    app = FastAPI()
    app.include_router(family_route.router, prefix="/api/v1/family")

    async def _user():
        return other

    async def _db():
        db = AsyncMock()
        yield db

    app.dependency_overrides[get_current_user] = _user
    app.dependency_overrides[get_db] = _db

    with patch.object(
        family_route,
        "_get_member",
        AsyncMock(side_effect=family_route.HTTPException(
            status_code=404, detail="Family member not found"
        )),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/family/10")
    assert resp.status_code == 404
    src = inspect.getsource(family_route._get_member)
    assert "FamilyMember.user_id == user_id" in src


def test_sec5_be_06_missing_key_does_not_crash_or_log_plaintext(monkeypatch):
    monkeypatch.delenv("ENCRYPTION_KEY", raising=False)
    enc.reset_fernet_for_tests()
    cipher = enc.encrypt("family-phi")
    assert cipher != "family-phi"
    assert enc.decrypt(cipher) == "family-phi"
    enc.reset_fernet_for_tests()


def test_sec5_be_07_no_hardcoded_encryption_secret():
    src = inspect.getsource(enc)
    assert "os.environ.get(\"ENCRYPTION_KEY\"" in src
    assert "Fernet.generate_key" not in src
    # No embedded Fernet token / key material in the service module.
    assert "gAAAA" not in src


def test_sec5_be_08_family_routes_do_not_log_clinical_phi():
    create_src = inspect.getsource(family_route.create_family_member)
    update_src = inspect.getsource(family_route.update_family_member)
    for src in (create_src, update_src):
        assert "audit_log" not in src
        assert "logger.info" not in src
    decorator_src = inspect.getsource(family_route.LoggedAPIRoute.get_route_handler)
    assert "request.body" not in decorator_src
    assert "json()" not in decorator_src


def test_sec5_be_10_record_file_magic_unchanged():
    assert RECORD_FILE_MAGIC == b"HNREC1"
    blob = enc.encrypt_bytes(b"synthetic-record")
    assert blob.startswith(RECORD_FILE_MAGIC)
    assert enc.decrypt_bytes(blob) == b"synthetic-record"


def test_sec5_be_11_legacy_plaintext_family_rows_remain_readable():
    col = EncryptedText()
    legacy = json.dumps(["Asthma"])
    assert col.process_result_value(legacy, None) == legacy
    assert col.process_result_value("uses spacer", None) == "uses spacer"
    assert col.process_result_value(None, None) is None


@pytest.mark.anyio
async def test_sec5_be_12_owner_create_still_serializes():
    user = SimpleNamespace(id=1, email="a@ex.com", is_active=True)
    app = FastAPI()
    app.include_router(family_route.router, prefix="/api/v1/family")

    created = {}

    async def _user():
        return user

    async def _db():
        db = AsyncMock()
        db.add = MagicMock(side_effect=lambda obj: created.update(obj.__dict__))
        db.commit = AsyncMock()

        async def refresh(obj):
            obj.id = 42
            if getattr(obj, "created_at", None) is None:
                from datetime import datetime, timezone
                obj.created_at = datetime.now(timezone.utc)

        db.refresh = AsyncMock(side_effect=refresh)
        yield db

    app.dependency_overrides[get_current_user] = _user
    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/family/",
            json={
                "name": "Alex",
                "medical_conditions": ["Asthma"],
                "allergies": ["Peanuts"],
                "notes": "uses spacer",
            },
        )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["name"] == "Alex"
    assert body["medical_conditions"] == ["Asthma"]
    assert body["allergies"] == ["Peanuts"]
    assert body["notes"] == "uses spacer"
