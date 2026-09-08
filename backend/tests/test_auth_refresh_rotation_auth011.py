"""HN-AUTH-011 — refresh token rotate-on-use (AUTH011-BE-01..08 + concurrency)."""
from __future__ import annotations

import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from jose import jwt

from app.api.routes import auth as auth_route
from app.core.config import settings
from app.core.database import get_db
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    refresh_token_ttl_seconds,
)
from app.services.refresh_token_store import RefreshTokenStore, _reset_memory_store_for_tests


def _user(uid: int = 1, tv: int = 0, name: str = "Alice"):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@example.com",
        name=name,
        is_active=True,
        token_version=tv,
    )


def _db_returning(user):
    db = AsyncMock()
    result = MagicMock()
    result.scalar_one_or_none.return_value = user
    db.execute = AsyncMock(return_value=result)
    db.commit = AsyncMock()
    return db


@pytest.fixture(autouse=True)
def _clear_refresh_store():
    _reset_memory_store_for_tests()
    yield
    _reset_memory_store_for_tests()


@pytest.fixture
def auth_app():
    def _make(user):
        app = FastAPI()
        app.include_router(auth_route.router, prefix="/api/v1/auth")

        async def _override_db():
            yield _db_returning(user)

        app.dependency_overrides[get_db] = _override_db
        return app, user

    return _make


async def _register_refresh(token: str, user_id: int) -> str:
    payload = decode_token(token)
    jti = payload["jti"]
    ok = await RefreshTokenStore.register(jti, user_id, refresh_token_ttl_seconds())
    assert ok is True
    return jti


@pytest.mark.anyio
async def test_auth011_be_01_02_valid_refresh_returns_new_refresh(auth_app):
    """AUTH011-BE-01 / BE-02: valid refresh succeeds and returns a new refresh token."""
    app, user = auth_app(_user(tv=0))
    r1 = create_refresh_token({"sub": "1"}, token_version=0)
    await _register_refresh(r1, 1)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": r1})

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "access_token" in body
    assert "refresh_token" in body
    r2 = body["refresh_token"]
    assert r2 != r1
    assert decode_token(r2).get("jti")
    assert decode_token(r2).get("jti") != decode_token(r1).get("jti")


@pytest.mark.anyio
async def test_auth011_be_03_old_refresh_rejected_after_rotation(auth_app):
    """AUTH011-BE-03: R1 replay after R1→R2 is rejected."""
    app, user = auth_app(_user(tv=0))
    r1 = create_refresh_token({"sub": "1"}, token_version=0)
    await _register_refresh(r1, 1)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        first = await client.post("/api/v1/auth/refresh", json={"refresh_token": r1})
        assert first.status_code == 200
        replay = await client.post("/api/v1/auth/refresh", json={"refresh_token": r1})

    assert replay.status_code == 401
    assert "Invalid refresh token" in replay.json()["detail"]


@pytest.mark.anyio
async def test_auth011_be_04_05_second_generation_rotates_once(auth_app):
    """AUTH011-BE-04 / BE-05: R2→R3 succeeds; R2 replay rejected."""
    app, user = auth_app(_user(tv=0))
    r1 = create_refresh_token({"sub": "1"}, token_version=0)
    await _register_refresh(r1, 1)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        r1_resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": r1})
        assert r1_resp.status_code == 200
        r2 = r1_resp.json()["refresh_token"]

        r2_resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": r2})
        assert r2_resp.status_code == 200
        r3 = r2_resp.json()["refresh_token"]
        assert r3 != r2

        r2_replay = await client.post("/api/v1/auth/refresh", json={"refresh_token": r2})
        assert r2_replay.status_code == 401


@pytest.mark.anyio
async def test_auth011_be_06_invalid_and_expired_refresh_rejected(auth_app):
    """AUTH011-BE-06: malformed / wrong type / expired / missing jti rejected."""
    app, user = auth_app(_user(tv=0))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        malformed = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": "not-a-jwt"},
        )
        assert malformed.status_code == 401

        access = create_access_token({"sub": "1"}, token_version=0)
        wrong_type = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": access},
        )
        assert wrong_type.status_code == 401

        # Expired refresh JWT
        expired = jwt.encode(
            {
                "sub": "1",
                "type": "refresh",
                "tv": 0,
                "jti": "expired-jti",
                "exp": 1,  # 1970
            },
            settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
        )
        expired_resp = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": expired},
        )
        assert expired_resp.status_code == 401

        # Valid signature/type but never registered jti → fail closed
        orphan = create_refresh_token({"sub": "1"}, token_version=0)
        orphan_resp = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": orphan},
        )
        assert orphan_resp.status_code == 401


@pytest.mark.anyio
async def test_auth011_be_07_logout_token_version_still_blocks_refresh(auth_app):
    """AUTH011-BE-07: logout/token_version invalidation still rejects refresh."""
    app, user = auth_app(_user(tv=0))
    access = create_access_token({"sub": "1"}, token_version=0)
    refresh = create_refresh_token({"sub": "1"}, token_version=0)
    await _register_refresh(refresh, 1)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        logout = await client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {access}"},
        )
        assert logout.status_code == 200
        assert user.token_version == 1

        refresh_resp = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": refresh},
        )
    assert refresh_resp.status_code == 401
    assert "revoked" in refresh_resp.json()["detail"].lower()


@pytest.mark.anyio
async def test_auth011_be_08_independent_session_survives_other_rotation(auth_app):
    """AUTH011-BE-08: rotating session A does not invalidate session B."""
    app, user = auth_app(_user(tv=0))
    r_a = create_refresh_token({"sub": "1"}, token_version=0)
    r_b = create_refresh_token({"sub": "1"}, token_version=0)
    assert decode_token(r_a)["jti"] != decode_token(r_b)["jti"]
    await _register_refresh(r_a, 1)
    await _register_refresh(r_b, 1)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        a_resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": r_a})
        assert a_resp.status_code == 200
        r_a2 = a_resp.json()["refresh_token"]

        # R_A consumed
        a_replay = await client.post("/api/v1/auth/refresh", json={"refresh_token": r_a})
        assert a_replay.status_code == 401

        # R_B still valid
        b_resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": r_b})
        assert b_resp.status_code == 200
        assert b_resp.json()["refresh_token"] != r_b

        # Successor of A still valid
        a2_resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": r_a2})
        assert a2_resp.status_code == 200


@pytest.mark.anyio
async def test_auth011_concurrent_same_refresh_only_one_wins(auth_app):
    """Concurrent refresh of R1: exactly one successor; loser gets 401."""
    app, user = auth_app(_user(tv=0))
    r1 = create_refresh_token({"sub": "1"}, token_version=0)
    await _register_refresh(r1, 1)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        results = await asyncio.gather(
            client.post("/api/v1/auth/refresh", json={"refresh_token": r1}),
            client.post("/api/v1/auth/refresh", json={"refresh_token": r1}),
            client.post("/api/v1/auth/refresh", json={"refresh_token": r1}),
        )

    statuses = sorted(r.status_code for r in results)
    assert statuses.count(200) == 1
    assert statuses.count(401) == 2


@pytest.mark.anyio
async def test_auth011_refresh_tokens_embed_jti():
    """New refresh tokens always carry a unique jti claim."""
    t1 = create_refresh_token({"sub": "9"}, token_version=0)
    t2 = create_refresh_token({"sub": "9"}, token_version=0)
    p1 = decode_token(t1)
    p2 = decode_token(t2)
    assert p1.get("jti")
    assert p2.get("jti")
    assert p1["jti"] != p2["jti"]
    assert p1.get("type") == "refresh"


@pytest.mark.anyio
async def test_auth011_store_consume_is_atomic_memory():
    """Store-level: second consume of same jti fails."""
    jti = "test-jti-atomic"
    assert await RefreshTokenStore.register(jti, 42, 60) is True
    assert await RefreshTokenStore.consume(jti, 42) is True
    assert await RefreshTokenStore.consume(jti, 42) is False


@pytest.mark.anyio
async def test_auth011_store_rejects_wrong_user():
    jti = "test-jti-user"
    assert await RefreshTokenStore.register(jti, 1, 60) is True
    assert await RefreshTokenStore.consume(jti, 2) is False
    # Original binding remains for the rightful owner after wrong-user attempt
    assert await RefreshTokenStore.consume(jti, 1) is True
