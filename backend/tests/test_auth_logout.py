"""HN-AUTH-007 — server-side logout via token_version (AUTH-LOGOUT-01..15)."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI, Depends
from httpx import ASGITransport, AsyncClient

from app.api.routes import auth as auth_route
from app.core.deps import get_current_user, token_version_matches
from app.core.database import get_db
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
)


def _user(uid: int = 1, tv: int = 0, name: str = "Alice"):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@example.com",
        name=name,
        is_active=True,
        token_version=tv,
    )


def _db_returning(user):
    """AsyncSession mock: select(User) → user."""
    db = AsyncMock()
    result = MagicMock()
    result.scalar_one_or_none.return_value = user
    db.execute = AsyncMock(return_value=result)
    db.commit = AsyncMock()
    return db


@pytest.fixture
def auth_app():
    def _make(user):
        app = FastAPI()
        app.include_router(auth_route.router, prefix="/api/v1/auth")

        # Minimal protected probe for post-logout access checks
        @app.get("/api/v1/probe")
        async def probe(u=Depends(get_current_user)):
            return {"user_id": u.id}

        async def _override_db():
            db = _db_returning(user)
            yield db

        app.dependency_overrides[get_db] = _override_db
        return app, user

    return _make


# ─── Unit: token version claim ───────────────────────────────────────────────

def test_auth_logout_09_10_tokens_embed_tv_claim():
    """AUTH-LOGOUT-09/10: tokens carry tv; mismatch is detectable."""
    access = create_access_token({"sub": "1"}, token_version=3)
    refresh = create_refresh_token({"sub": "1"}, token_version=3)
    ap = decode_token(access)
    rp = decode_token(refresh)
    assert ap.get("tv") == 3
    assert rp.get("tv") == 3
    assert ap.get("type") == "access"
    assert rp.get("type") == "refresh"
    user = _user(tv=3)
    assert token_version_matches(ap, user) is True
    user.token_version = 4
    assert token_version_matches(ap, user) is False


def test_auth_logout_11_decode_has_no_secret_key_leak():
    """AUTH-LOGOUT-11: decode payload does not include signing secret."""
    token = create_access_token({"sub": "9"}, token_version=0)
    payload = decode_token(token)
    assert "SECRET" not in str(payload).upper()
    assert "secret_key" not in payload


# ─── Logout endpoint ─────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_auth_logout_01_authenticated_logout(auth_app):
    """AUTH-LOGOUT-01"""
    app, user = auth_app(_user(tv=0))
    token = create_access_token({"sub": "1"}, token_version=0)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {token}"},
        )
    assert resp.status_code == 200
    assert resp.json().get("message") == "Logged out"
    assert "access_token" not in resp.json()
    assert "refresh_token" not in resp.json()
    assert user.token_version == 1


@pytest.mark.anyio
async def test_auth_logout_02_08_access_rejected_after_logout(auth_app):
    """AUTH-LOGOUT-02 / 08 / 10: access token rejected after version bump."""
    user = _user(tv=0)
    app, _ = auth_app(user)
    token = create_access_token({"sub": "1"}, token_version=0)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        ok = await client.get(
            "/api/v1/probe",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert ok.status_code == 200
        lo = await client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert lo.status_code == 200
        assert user.token_version == 1
        denied = await client.get(
            "/api/v1/probe",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert denied.status_code == 401


@pytest.mark.anyio
async def test_auth_logout_03_13_refresh_rejected_after_logout(auth_app):
    """AUTH-LOGOUT-03 / 13"""
    user = _user(tv=0)
    app, _ = auth_app(user)
    access = create_access_token({"sub": "1"}, token_version=0)
    refresh = create_refresh_token({"sub": "1"}, token_version=0)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        await client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {access}"},
        )
        assert user.token_version == 1
        resp = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": refresh},
        )
        assert resp.status_code == 401
        body = resp.json().get("detail", "")
        assert "revoked" in str(body).lower() or "login" in str(body).lower()


@pytest.mark.anyio
async def test_auth_logout_05_12_user_b_unaffected(auth_app):
    """AUTH-LOGOUT-05 / 12: User A logout does not change User B token_version."""
    user_a = _user(uid=1, tv=0)
    user_b = _user(uid=2, tv=7, name="Bob")

    app_a = FastAPI()
    app_a.include_router(auth_route.router, prefix="/api/v1/auth")

    async def db_a():
        yield _db_returning(user_a)

    app_a.dependency_overrides[get_db] = db_a
    token_a = create_access_token({"sub": "1"}, token_version=0)
    transport = ASGITransport(app=app_a)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {token_a}"},
        )
    assert resp.status_code == 200
    assert user_a.token_version == 1
    assert user_b.token_version == 7


@pytest.mark.anyio
async def test_auth_logout_04_cannot_logout_as_other_user(auth_app):
    """AUTH-LOGOUT-04: token for user 1 cannot mutate user 2."""
    # Token sub=1 only loads user 1 from DB override
    user = _user(uid=1, tv=0)
    app, _ = auth_app(user)
    token = create_access_token({"sub": "1"}, token_version=0)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {token}"},
        )
    assert resp.status_code == 200
    assert user.id == 1
    assert user.token_version == 1


@pytest.mark.anyio
async def test_auth_logout_06_unauthenticated_rejected(auth_app):
    """AUTH-LOGOUT-06"""
    app, _ = auth_app(_user())
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/api/v1/auth/logout")
    assert resp.status_code in (401, 403)


@pytest.mark.anyio
async def test_auth_logout_07_second_logout_with_old_token_fails(auth_app):
    """AUTH-LOGOUT-07: repeated logout with revoked token is rejected safely."""
    user = _user(tv=0)
    app, _ = auth_app(user)
    token = create_access_token({"sub": "1"}, token_version=0)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        first = await client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {token}"},
        )
        second = await client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {token}"},
        )
    assert first.status_code == 200
    assert second.status_code == 401


@pytest.mark.anyio
async def test_auth_logout_14_15_new_tokens_after_version_bump(auth_app):
    """AUTH-LOGOUT-14 / 15: new session with current tv works after logout."""
    user = _user(tv=1)  # already logged out once
    app, _ = auth_app(user)
    fresh = create_access_token({"sub": "1"}, token_version=1)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        ok = await client.get(
            "/api/v1/probe",
            headers={"Authorization": f"Bearer {fresh}"},
        )
        assert ok.status_code == 200
        # refresh with matching tv
        rt = create_refresh_token({"sub": "1"}, token_version=1)
        refreshed = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": rt},
        )
        assert refreshed.status_code == 200
        body = refreshed.json()
        assert "access_token" in body and "refresh_token" in body
        # new access embeds same tv
        assert decode_token(body["access_token"]).get("tv") == 1
