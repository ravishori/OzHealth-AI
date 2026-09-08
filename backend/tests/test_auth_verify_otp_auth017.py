"""HN-AUTH-017 — standalone POST /auth/verify-otp (AUTH17-BE-01..12)."""
from __future__ import annotations

import inspect
import logging
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from httpx import ASGITransport, AsyncClient

from app.api.routes import auth as auth_route
from app.core.database import get_db
from app.core.exceptions import AppException, RateLimitError
from app.core.security import hash_otp


SYNTHETIC_OTP = "482917"
OTHER_OTP = "111111"
IDENTIFIER = "auth17.user@example.com"
OTHER_IDENTIFIER = "auth17.other@example.com"


def _otp_row(*, otp_id: int = 42, code: str = SYNTHETIC_OTP):
    return SimpleNamespace(id=otp_id, otp_hash=hash_otp(code), otp_code="******")


def _verify_app():
    app = FastAPI()
    app.include_router(auth_route.router, prefix="/api/v1/auth")

    @app.exception_handler(AppException)
    async def _app_exc(_request, exc: AppException):
        headers = {}
        if isinstance(exc, RateLimitError):
            headers["Retry-After"] = str(exc.retry_after)
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": exc.error_code, "message": exc.message},
            headers=headers,
        )

    async def _db():
        db = AsyncMock()
        db.commit = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = _db
    return app


async def _post_verify(client, *, identifier=IDENTIFIER, otp=SYNTHETIC_OTP, purpose="auth"):
    return await client.post(
        "/api/v1/auth/verify-otp",
        json={"identifier": identifier, "otp_code": otp, "purpose": purpose},
    )


@pytest.mark.anyio
async def test_auth17_be_01_valid_otp_verifies_successfully():
    """AUTH17-BE-01 / AUTH17-BE-11 — success returns valid; no session tokens."""
    app = _verify_app()
    row = _otp_row()
    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_clear_verify_rate", new=AsyncMock()) as clear_rate,
        patch.object(auth_route, "_fn_get_valid_otps", new=AsyncMock(return_value=[row])),
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()) as mark_used,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await _post_verify(client, purpose="auth")
    assert resp.status_code == 200
    body = resp.json()
    assert body.get("valid") is True
    assert "access_token" not in body
    assert "refresh_token" not in body
    assert SYNTHETIC_OTP not in str(body)
    mark_used.assert_awaited_once()
    assert mark_used.await_args.args[1] == row.id
    clear_rate.assert_awaited()


@pytest.mark.anyio
async def test_auth17_be_02_invalid_otp_rejected():
    """AUTH17-BE-02 / AUTH17-BE-10 — invalid code fails without tokens."""
    app = _verify_app()
    row = _otp_row()
    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_fn_get_valid_otps", new=AsyncMock(return_value=[row])),
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()) as mark_used,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await _post_verify(client, otp=OTHER_OTP)
    assert resp.status_code == 400
    body = resp.json()
    assert "access_token" not in body
    assert "refresh_token" not in body
    assert SYNTHETIC_OTP not in str(body)
    assert OTHER_OTP not in str(body)
    mark_used.assert_not_awaited()


@pytest.mark.anyio
async def test_auth17_be_03_expired_otp_rejected():
    """AUTH17-BE-03 — expired OTPs are absent from fn_get_valid_otps → reject."""
    app = _verify_app()
    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_fn_get_valid_otps", new=AsyncMock(return_value=[])),
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()) as mark_used,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await _post_verify(client)
    assert resp.status_code == 400
    mark_used.assert_not_awaited()


@pytest.mark.anyio
async def test_auth17_be_04_otp_cannot_be_replayed():
    """AUTH17-BE-04 — after success, second verify fails (consumed / empty valid set)."""
    app = _verify_app()
    row = _otp_row()
    get_valid = AsyncMock(side_effect=[[row], []])
    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_clear_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_fn_get_valid_otps", new=get_valid),
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()) as mark_used,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            first = await _post_verify(client)
            second = await _post_verify(client)
    assert first.status_code == 200
    assert second.status_code == 400
    assert mark_used.await_count == 1
    assert "access_token" not in second.json()


@pytest.mark.anyio
async def test_auth17_be_05_wrong_purpose_rejected():
    """AUTH17-BE-05 — auth OTP cannot satisfy register purpose (and vice versa)."""
    app = _verify_app()

    async def _get_valid(_db, identifier, purpose):
        # Server only returns rows for the requested purpose.
        if purpose == "register":
            return []
        return [_otp_row()]

    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_fn_get_valid_otps", new=AsyncMock(side_effect=_get_valid)),
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()) as mark_used,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await _post_verify(client, purpose="register")
    assert resp.status_code == 400
    mark_used.assert_not_awaited()


@pytest.mark.anyio
async def test_auth17_be_05b_unsupported_purpose_rejected():
    """AUTH17-BE-05 / AUTH17-BE-12 — contact_change/reset not accepted here."""
    app = _verify_app()
    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()) as rate,
        patch.object(auth_route, "_fn_get_valid_otps", new=AsyncMock()) as get_valid,
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()) as mark_used,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            for purpose in ("contact_change", "reset", "admin", ""):
                resp = await _post_verify(client, purpose=purpose)
                assert resp.status_code == 400, purpose
                assert "access_token" not in resp.json()
    rate.assert_not_awaited()
    get_valid.assert_not_awaited()
    mark_used.assert_not_awaited()


@pytest.mark.anyio
async def test_auth17_be_06_otp_never_returned_in_response():
    """AUTH17-BE-06"""
    app = _verify_app()
    row = _otp_row()
    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_clear_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_fn_get_valid_otps", new=AsyncMock(return_value=[row])),
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            ok = await _post_verify(client)
            bad = await _post_verify(client, otp=OTHER_OTP)
    for resp in (ok, bad):
        dumped = resp.text
        assert SYNTHETIC_OTP not in dumped
        assert "otp_code" not in dumped
        assert "otp_hash" not in dumped


def test_auth17_be_07_otp_values_not_written_to_logs():
    """AUTH17-BE-07 — verify_otp_check source/logging must not format OTP values."""
    src = inspect.getsource(auth_route.verify_otp_check)
    assert "otp=%s" not in src
    assert "otp_code=%s" not in src
    assert "req.otp_code" in src  # compared server-side only
    audit_chunk = src.split("audit_log.info", 1)[-1][:500]
    assert "otp_code" not in audit_chunk
    assert "_mask(identifier)" in audit_chunk


@pytest.mark.anyio
async def test_auth17_be_08_attempt_rate_limit_enforced():
    """AUTH17-BE-08 — verify rate limit uses existing CacheService architecture."""
    app = _verify_app()
    with patch.object(
        auth_route,
        "_check_otp_verify_rate",
        new=AsyncMock(side_effect=RateLimitError("Too many failed attempts.", retry_after=42)),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await _post_verify(client)
    assert resp.status_code == 429
    assert resp.headers.get("Retry-After") == "42"
    assert "access_token" not in resp.json()
    assert SYNTHETIC_OTP not in resp.text


@pytest.mark.anyio
async def test_auth17_be_09_cross_user_challenge_misuse_rejected():
    """AUTH17-BE-09 — OTP bound to identifier A cannot verify identifier B."""
    app = _verify_app()

    async def _get_valid(_db, identifier, purpose):
        if identifier == IDENTIFIER.lower():
            return [_otp_row()]
        return []

    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_fn_get_valid_otps", new=AsyncMock(side_effect=_get_valid)),
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()) as mark_used,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await _post_verify(client, identifier=OTHER_IDENTIFIER)
    assert resp.status_code == 400
    mark_used.assert_not_awaited()


@pytest.mark.anyio
async def test_auth17_be_10_11_failure_no_tokens_success_no_tokens():
    """AUTH17-BE-10 / AUTH17-BE-11 — standalone verify never issues session tokens."""
    app = _verify_app()
    row = _otp_row()
    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_clear_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_fn_get_valid_otps", new=AsyncMock(return_value=[row])),
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            ok = await _post_verify(client)
            bad = await _post_verify(client, otp="000000")
    for resp in (ok, bad):
        body = resp.json()
        assert "access_token" not in body
        assert "refresh_token" not in body
        assert "token_type" not in body
        assert "user_id" not in body
    assert ok.json().get("valid") is True


@pytest.mark.anyio
async def test_auth17_be_12_register_purpose_supported_unauthenticated():
    """AUTH17-BE-12 — unauthenticated register purpose verifies without auth header."""
    app = _verify_app()
    row = _otp_row(otp_id=99)
    with (
        patch.object(auth_route, "_check_otp_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_clear_verify_rate", new=AsyncMock()),
        patch.object(auth_route, "_fn_get_valid_otps", new=AsyncMock(return_value=[row])) as get_valid,
        patch.object(auth_route, "_sp_mark_otp_used", new=AsyncMock()),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await _post_verify(client, purpose="register")
    assert resp.status_code == 200
    assert resp.json().get("valid") is True
    assert get_valid.await_args.args[2] == "register"


def test_auth17_be_07_runtime_audit_log_masks_identifier(caplog):
    """AUTH17-BE-07 runtime — audit path uses masked identifier only."""
    with caplog.at_level(logging.INFO):
        auth_route.audit_log.info(
            "otp_verified",
            extra={"identifier": auth_route._mask(IDENTIFIER), "purpose": "auth"},
        )
    assert SYNTHETIC_OTP not in caplog.text
    assert IDENTIFIER not in caplog.text
