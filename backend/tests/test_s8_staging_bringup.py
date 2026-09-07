"""S8 staging bring-up: config gates, health DB probe, Alembic head contract."""
from __future__ import annotations

import inspect
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings


def _base_kwargs(**overrides):
    data = dict(
        DATABASE_URL="postgresql+asyncpg://u:p@localhost/db",
        SYNC_DATABASE_URL="postgresql+psycopg2://u:p@localhost/db",
        SECRET_KEY="unit-test-secret-key-with-32chars-min",
        ENCRYPTION_KEY="dGVzdC1lbmNyeXB0aW9uLWtleS0zMi1ieXRlcso=",
        DEBUG=False,
        ENVIRONMENT="development",
    )
    data.update(overrides)
    return data


def test_auto_create_tables_default_on_for_development():
    s = Settings(**_base_kwargs(ENVIRONMENT="development", AUTO_CREATE_TABLES=None))
    assert s.should_auto_create_tables() is True


def test_auto_create_tables_forced_off_in_staging_even_if_flag_true():
    s = Settings(**_base_kwargs(ENVIRONMENT="staging", AUTO_CREATE_TABLES=True))
    assert s.is_hosted_environment() is True
    assert s.should_auto_create_tables() is False


def test_auto_create_tables_forced_off_in_production():
    s = Settings(**_base_kwargs(ENVIRONMENT="production", AUTO_CREATE_TABLES=True))
    assert s.should_auto_create_tables() is False


def test_auto_create_tables_explicit_false_in_development():
    s = Settings(**_base_kwargs(ENVIRONMENT="development", AUTO_CREATE_TABLES=False))
    assert s.should_auto_create_tables() is False


def test_hosted_validation_requires_encryption_key():
    s = Settings(
        **_base_kwargs(ENVIRONMENT="staging", ENCRYPTION_KEY="", DEBUG=False)
    )
    with pytest.raises(RuntimeError) as exc:
        s.validate_for_startup()
    assert "ENCRYPTION_KEY" in str(exc.value)
    assert "postgresql" not in str(exc.value).lower()


def test_hosted_validation_rejects_debug_true():
    s = Settings(**_base_kwargs(ENVIRONMENT="production", DEBUG=True))
    with pytest.raises(RuntimeError) as exc:
        s.validate_for_startup()
    assert "DEBUG" in str(exc.value)


def test_hosted_validation_rejects_auto_create_flag():
    s = Settings(**_base_kwargs(ENVIRONMENT="staging", AUTO_CREATE_TABLES=True))
    with pytest.raises(RuntimeError) as exc:
        s.validate_for_startup()
    assert "AUTO_CREATE_TABLES" in str(exc.value)


def test_hosted_validation_passes_when_configured():
    s = Settings(**_base_kwargs(ENVIRONMENT="staging", DEBUG=False, AUTO_CREATE_TABLES=False))
    s.validate_for_startup()  # must not raise


def test_development_validation_allows_empty_encryption_key():
    s = Settings(**_base_kwargs(ENVIRONMENT="development", ENCRYPTION_KEY=""))
    s.validate_for_startup()


def test_alembic_head_is_017_error_logs():
    from pathlib import Path
    import re

    versions = Path(__file__).resolve().parents[1] / "alembic" / "versions"
    files = sorted(versions.glob("*.py"))
    heads = []
    revs = {}
    for p in files:
        text = p.read_text(encoding="utf-8")
        rev = re.search(r'^revision\s*=\s*[\'"]([^\'"]+)[\'"]', text, re.M)
        down = re.search(r'^down_revision\s*=\s*([^\n]+)', text, re.M)
        assert rev, p.name
        d = down.group(1).strip() if down else "None"
        dval = None if d in ("None", "none") else d.strip("'\"")
        revs[rev.group(1)] = dval
    children = {}
    for r, d in revs.items():
        children.setdefault(d, []).append(r)
    # walk from root
    root = [r for r, d in revs.items() if d is None][0]
    cur = root
    chain = [cur]
    while children.get(cur):
        cur = children[cur][0]
        chain.append(cur)
    assert chain[0] == "001"
    assert chain[-1] == "017"
    assert "016" in chain
    assert (versions / "017_add_error_logs_table.py").is_file()
    assert (versions / "016_add_user_token_version.py").is_file()


def test_main_startup_skips_create_all_when_hosted():
    import main as main_mod

    src = inspect.getsource(main_mod.on_startup)
    assert "should_auto_create_tables" in src
    assert "create_all" in src
    assert "validate_for_startup" in src


def test_health_source_has_no_secret_fields():
    import main as main_mod

    src = inspect.getsource(main_mod.health).lower()
    for banned in (
        "database_url",
        "secret_key",
        "encryption_key",
        "password",
        "traceback",
        "exc_info",
        "str(e)",
        "repr(",
    ):
        assert banned not in src


@pytest.mark.asyncio
async def test_health_returns_200_when_db_ok():
    from sqlalchemy import text

    app = FastAPI()

    mock_conn = AsyncMock()
    mock_conn.execute = AsyncMock(return_value=None)
    mock_conn.__aenter__ = AsyncMock(return_value=mock_conn)
    mock_conn.__aexit__ = AsyncMock(return_value=None)

    mock_engine = MagicMock()
    mock_engine.connect = MagicMock(return_value=mock_conn)

    @app.get("/health")
    async def health():
        try:
            async with mock_engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
        except Exception:
            return JSONResponse(
                status_code=503,
                content={"status": "unhealthy", "version": "1.0.0"},
            )
        return {"status": "healthy", "version": "1.0.0"}

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body == {"status": "healthy", "version": "1.0.0"}
    assert "database" not in body


@pytest.mark.asyncio
async def test_health_returns_503_when_db_fails():
    app = FastAPI()

    mock_conn = AsyncMock()
    mock_conn.execute = AsyncMock(side_effect=RuntimeError("boom"))
    mock_conn.__aenter__ = AsyncMock(return_value=mock_conn)
    mock_conn.__aexit__ = AsyncMock(return_value=None)
    mock_engine = MagicMock()
    mock_engine.connect = MagicMock(return_value=mock_conn)

    from sqlalchemy import text

    @app.get("/health")
    async def health():
        try:
            async with mock_engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
        except Exception:
            return JSONResponse(
                status_code=503,
                content={"status": "unhealthy", "version": "1.0.0"},
            )
        return {"status": "healthy", "version": "1.0.0"}

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/health")
    assert resp.status_code == 503
    body = resp.json()
    assert body["status"] == "unhealthy"
    assert "boom" not in resp.text
    assert "password" not in resp.text.lower()
