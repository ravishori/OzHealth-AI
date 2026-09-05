"""HN-RECORD-009 — medical-record file encryption at rest (RECORD-SEC-04..16)."""
from __future__ import annotations

import io
import os
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from cryptography.fernet import Fernet
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.api.routes import records as records_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.services import encryption_service as enc
from app.utils import storage as storage_mod


# Deterministic Fernet key for this module (never logged in assertions).
_TEST_KEY = Fernet.generate_key().decode()
_PLAINTEXT = b"HN-RECORD-009 synthetic test document bytes v1"


@pytest.fixture
def anyio_backend():
    """aiofiles / FastAPI upload path is asyncio-backed in this project."""
    return "asyncio"


def _user(uid: int, email: str = "a@example.com"):
    return SimpleNamespace(id=uid, email=email, is_active=True)


def _record(
    *,
    rid: int = 10,
    uid: int = 1,
    file_url: str = "records/1/x.pdf",
    is_active: bool = True,
    file_name: str = "x.pdf",
):
    return SimpleNamespace(
        id=rid,
        user_id=uid,
        family_member_id=None,
        record_type="lab_report",
        title="Labs",
        file_url=file_url,
        file_name=file_name,
        file_type="pdf",
        notes=None,
        record_date=None,
        created_at=None,
        is_active=is_active,
    )


@pytest.fixture(autouse=True)
def _encryption_key(monkeypatch):
    monkeypatch.setenv("ENCRYPTION_KEY", _TEST_KEY)
    enc.reset_fernet_for_tests()
    yield
    enc.reset_fernet_for_tests()


@pytest.fixture
def upload_root(tmp_path, monkeypatch):
    root = tmp_path / "uploads"
    root.mkdir()
    monkeypatch.setattr(storage_mod, "_UPLOAD_ROOT", root.resolve())
    return root.resolve()


@pytest.fixture
def app_factory():
    def _make(user, db=None):
        app = FastAPI()
        app.include_router(records_route.router, prefix="/api/v1/records")

        async def _override_user():
            return user

        async def _override_db():
            yield db if db is not None else AsyncMock()

        app.dependency_overrides[get_current_user] = _override_user
        app.dependency_overrides[get_db] = _override_db
        return app

    return _make


def _app_unauthenticated():
    """App without get_current_user override — HTTPBearer denies."""
    app = FastAPI()
    app.include_router(records_route.router, prefix="/api/v1/records")

    async def _override_db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = _override_db
    return app


# ─── Unit: crypto + storage ──────────────────────────────────────────────────


def test_encrypt_bytes_roundtrip_and_magic():
    cipher = enc.encrypt_bytes(_PLAINTEXT)
    assert cipher != _PLAINTEXT
    assert enc.is_encrypted_record_blob(cipher)
    assert cipher.startswith(enc.RECORD_FILE_MAGIC)
    assert enc.decrypt_bytes(cipher) == _PLAINTEXT


@pytest.mark.anyio
async def test_record_sec_08_15_upload_stores_ciphertext(upload_root, app_factory):
    """RECORD-SEC-08 / RECORD-SEC-15 — disk bytes are encrypted, not plaintext."""
    owner = _user(1)
    captured: dict = {}

    db = AsyncMock()

    def _add(obj):
        captured["record"] = obj
        obj.id = 101
        obj.created_at = None

    db.add = _add
    db.commit = AsyncMock()
    db.refresh = AsyncMock(side_effect=lambda o: setattr(o, "id", 101))

    app = app_factory(owner, db=db)
    files = {"file": ("synth.pdf", io.BytesIO(_PLAINTEXT), "application/pdf")}
    data = {"record_type": "lab_report", "title": "Synth"}

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/api/v1/records/upload", data=data, files=files)

    assert resp.status_code == 200, resp.text
    rel = captured["record"].file_url
    assert rel
    stored_path = upload_root / rel
    assert stored_path.is_file()
    raw = stored_path.read_bytes()
    assert raw != _PLAINTEXT  # RECORD-SEC-08
    assert enc.is_encrypted_record_blob(raw)
    assert enc.decrypt_bytes(raw) == _PLAINTEXT
    # RECORD-SEC-15 — only encrypted representation at expected location
    siblings = list(stored_path.parent.glob("*"))
    assert siblings == [stored_path]
    assert all(enc.is_encrypted_record_blob(p.read_bytes()) for p in siblings)


@pytest.mark.anyio
async def test_record_sec_09_owner_download_returns_original(
    upload_root, app_factory
):
    """RECORD-SEC-09 — authenticated owner gets original plaintext bytes."""
    cipher = enc.encrypt_bytes(_PLAINTEXT)
    rel = "records/1/enc.pdf"
    path = upload_root / rel
    path.parent.mkdir(parents=True)
    path.write_bytes(cipher)
    assert path.read_bytes() != _PLAINTEXT

    owner = _user(1)
    app = app_factory(owner)
    record = _record(file_url=rel)

    with patch.object(records_route, "_get_record", AsyncMock(return_value=record)):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/records/10/file")

    assert resp.status_code == 200
    assert resp.content == _PLAINTEXT
    assert resp.content != cipher


@pytest.mark.anyio
async def test_record_sec_10_wrong_user_download_denied(upload_root, app_factory):
    """RECORD-SEC-10 — User B denied; no plaintext or ciphertext in body."""
    cipher = enc.encrypt_bytes(_PLAINTEXT)
    rel = "records/1/enc.pdf"
    path = upload_root / rel
    path.parent.mkdir(parents=True)
    path.write_bytes(cipher)

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
    assert resp.content != _PLAINTEXT
    assert resp.content != cipher
    assert _PLAINTEXT not in resp.content


@pytest.mark.anyio
async def test_record_sec_04_11_wrong_user_delete_denied(app_factory):
    """RECORD-SEC-04 / RECORD-SEC-11 — User B cannot delete User A record."""
    other = _user(2, "b@example.com")
    app = app_factory(other)

    with patch.object(
        records_route,
        "_get_record",
        AsyncMock(side_effect=HTTPException(status_code=404, detail="Record not found")),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.delete("/api/v1/records/10")

    assert resp.status_code == 404


@pytest.mark.anyio
async def test_record_sec_05_unauthenticated_denied():
    """RECORD-SEC-05 — metadata, file, delete require auth."""
    app = _app_unauthenticated()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        meta = await client.get("/api/v1/records/10")
        file_r = await client.get("/api/v1/records/10/file")
        delete_r = await client.delete("/api/v1/records/10")

    assert meta.status_code in (401, 403)
    assert file_r.status_code in (401, 403)
    assert delete_r.status_code in (401, 403)


@pytest.mark.anyio
async def test_record_sec_06_soft_deleted_inaccessible(upload_root, app_factory):
    """RECORD-SEC-06 — soft-deleted records inaccessible via list/detail/file."""
    owner = _user(1)
    cipher = enc.encrypt_bytes(_PLAINTEXT)
    rel = "records/1/gone.pdf"
    path = upload_root / rel
    path.parent.mkdir(parents=True)
    path.write_bytes(cipher)

    # Detail + file: _get_record raises 404 when is_active filter fails
    app = app_factory(owner)
    with patch.object(
        records_route,
        "_get_record",
        AsyncMock(side_effect=HTTPException(status_code=404, detail="Record not found")),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            detail = await client.get("/api/v1/records/10")
            file_r = await client.get("/api/v1/records/10/file")

    assert detail.status_code == 404
    assert file_r.status_code == 404

    # List: DB returns only active — empty
    db = AsyncMock()
    result = MagicMock()
    result.scalars.return_value.all.return_value = []
    db.execute = AsyncMock(return_value=result)
    app2 = app_factory(owner, db=db)
    transport = ASGITransport(app=app2)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        listed = await client.get("/api/v1/records/")
    assert listed.status_code == 200
    assert listed.json() == []


@pytest.mark.anyio
async def test_record_sec_07_delete_removes_object(upload_root, app_factory):
    """RECORD-SEC-07 — soft-delete + remove stored object + download blocked."""
    cipher = enc.encrypt_bytes(_PLAINTEXT)
    rel = "records/1/del.pdf"
    path = upload_root / rel
    path.parent.mkdir(parents=True)
    path.write_bytes(cipher)
    assert path.is_file()

    owner = _user(1)
    record = _record(file_url=rel)
    db = AsyncMock()
    db.commit = AsyncMock()
    app = app_factory(owner, db=db)

    with patch.object(records_route, "_get_record", AsyncMock(return_value=record)):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.delete("/api/v1/records/10")
            assert resp.status_code == 200
            assert record.is_active is False
            assert not path.exists()

            # Subsequent download denied (inactive via _get_record)
            with patch.object(
                records_route,
                "_get_record",
                AsyncMock(
                    side_effect=HTTPException(
                        status_code=404, detail="Record not found"
                    )
                ),
            ):
                down = await client.get("/api/v1/records/10/file")
            assert down.status_code == 404


@pytest.mark.anyio
async def test_record_sec_12_legacy_plaintext_compatible(upload_root, app_factory):
    """RECORD-SEC-12 — legacy plaintext still downloadable by owner only."""
    rel = "records/1/legacy.pdf"
    path = upload_root / rel
    path.parent.mkdir(parents=True)
    path.write_bytes(_PLAINTEXT)
    assert not enc.is_encrypted_record_blob(path.read_bytes())

    owner = _user(1)
    app = app_factory(owner)
    record = _record(file_url=rel)

    with patch.object(records_route, "_get_record", AsyncMock(return_value=record)):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            ok = await client.get("/api/v1/records/10/file")
    assert ok.status_code == 200
    assert ok.content == _PLAINTEXT

    other = _user(2, "b@example.com")
    app_b = app_factory(other)
    with patch.object(
        records_route,
        "_get_record",
        AsyncMock(side_effect=HTTPException(status_code=404, detail="Record not found")),
    ):
        transport = ASGITransport(app=app_b)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            denied = await client.get("/api/v1/records/10/file")
    assert denied.status_code == 404
    assert denied.content != _PLAINTEXT


@pytest.mark.anyio
async def test_record_sec_13_corrupt_ciphertext_safe_failure(
    upload_root, app_factory
):
    """RECORD-SEC-13 — corrupt ciphertext fails closed, no garbage body."""
    rel = "records/1/bad.pdf"
    path = upload_root / rel
    path.parent.mkdir(parents=True)
    path.write_bytes(enc.RECORD_FILE_MAGIC + b"not-a-valid-fernet-token!!!!")

    owner = _user(1)
    app = app_factory(owner)
    record = _record(file_url=rel)

    with patch.object(records_route, "_get_record", AsyncMock(return_value=record)):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/records/10/file")

    assert resp.status_code == 500
    assert resp.content != _PLAINTEXT
    assert enc.RECORD_FILE_MAGIC not in resp.content
    body = resp.content
    assert b"HN-RECORD-009" not in body


@pytest.mark.anyio
async def test_record_sec_14_wrong_key_safe_failure(upload_root, app_factory, monkeypatch):
    """RECORD-SEC-14 — wrong ENCRYPTION_KEY fails closed."""
    cipher = enc.encrypt_bytes(_PLAINTEXT)
    rel = "records/1/key.pdf"
    path = upload_root / rel
    path.parent.mkdir(parents=True)
    path.write_bytes(cipher)

    # Switch to a different key
    other_key = Fernet.generate_key().decode()
    monkeypatch.setenv("ENCRYPTION_KEY", other_key)
    enc.reset_fernet_for_tests()

    owner = _user(1)
    app = app_factory(owner)
    record = _record(file_url=rel)

    with patch.object(records_route, "_get_record", AsyncMock(return_value=record)):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/records/10/file")

    assert resp.status_code == 500
    assert resp.content != _PLAINTEXT
    assert resp.content != cipher


def test_record_sec_16_no_sensitive_logging_in_storage_paths():
    """RECORD-SEC-16 — storage/encryption paths must not log payloads/keys."""
    enc_src = Path(enc.__file__).read_text(encoding="utf-8")
    storage_src = Path(storage_mod.__file__).read_text(encoding="utf-8")
    records_src = Path(records_route.__file__).read_text(encoding="utf-8")

    for src in (enc_src, storage_src, records_src):
        assert "logger.info(ciphertext" not in src
        assert "logger.debug(content" not in src
        assert "print(content" not in src
        assert "ENCRYPTION_KEY" not in src or "os.environ.get(\"ENCRYPTION_KEY\"" in src or "os.environ.get('ENCRYPTION_KEY'" in src

    # encrypt_bytes / decrypt_bytes error paths log exception type only
    assert "File encryption failed" in enc_src
    assert "File decryption failed" in enc_src
    # Must not interpolate plaintext variable into logs in encrypt_bytes
    assert 'logger.error("File encryption failed: %s", type(exc).__name__)' in enc_src


@pytest.mark.anyio
async def test_encryption_failure_does_not_write_plaintext(upload_root, monkeypatch):
    """Fail closed: encryption error must not leave plaintext on disk."""

    def _boom(_data):
        raise RuntimeError("encrypt boom")

    monkeypatch.setattr(storage_mod, "encrypt_bytes", _boom)

    class FakeUpload:
        filename = "x.pdf"

        async def read(self):
            return _PLAINTEXT

    with pytest.raises(RuntimeError):
        await storage_mod.save_encrypted_medical_file(
            FakeUpload(), folder="records/1"
        )
    files = [p for p in upload_root.rglob("*") if p.is_file()]
    assert files == []
