"""HN-PROF-006 — lifestyle preferences (PROF006-01 .. PROF006-14)."""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from app.api.routes import users as users_route
from app.core.deps import get_current_user
from app.core.database import get_db
from app.schemas.user import UserUpdate
from app.services.encryption_service import EncryptedText, encrypt, reset_fernet_for_tests


def _user(uid: int = 1, lifestyle_raw: str | None = None):
    return SimpleNamespace(
        id=uid,
        name="Ada",
        email=f"u{uid}@ex.com",
        phone=None,
        phone2=None,
        age=30,
        gender="Female",
        blood_group="O+",
        health_conditions=None,
        allergies=None,
        lifestyle_preferences=lifestyle_raw,
        profile_image_url=None,
        suburb=None,
        city=None,
        state=None,
        postcode=None,
        is_verified=True,
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
        fcm_token=None,
        is_active=True,
        token_version=0,
    )


def _app(user=None):
    app = FastAPI()
    app.include_router(users_route.router, prefix="/api/v1/users")

    async def _override_db():
        db = AsyncMock()
        db.commit = AsyncMock()
        db.refresh = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = _override_db
    if user is not None:

        async def _override_user():
            return user

        app.dependency_overrides[get_current_user] = _override_user
    return app


# ── PROF006-01 / 07 / 08 ──────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_prof006_01_07_08_owner_can_read_lifestyle_including_empty():
    """PROF006-01/07/08 — owner reads decrypted lifestyle; empty is {}."""
    prefs = {"diet": "Vegetarian", "exercise": "Walk"}
    user = _user(1, lifestyle_raw=json.dumps(prefs))
    app = _app(user)

    with patch.object(users_route.CacheService, "get", new_callable=AsyncMock, return_value=None), patch.object(
        users_route.CacheService, "set", new_callable=AsyncMock
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/users/me")

    assert resp.status_code == 200
    body = resp.json()
    assert body["lifestyle_preferences"] == prefs

    empty_user = _user(1, lifestyle_raw=None)
    app2 = _app(empty_user)
    with patch.object(users_route.CacheService, "get", new_callable=AsyncMock, return_value=None), patch.object(
        users_route.CacheService, "set", new_callable=AsyncMock
    ):
        transport = ASGITransport(app=app2)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp2 = await client.get("/api/v1/users/me")
    assert resp2.status_code == 200
    assert resp2.json()["lifestyle_preferences"] == {}


# ── PROF006-02 ────────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_prof006_02_owner_can_update_lifestyle():
    """PROF006-02 — authenticated owner can update lifestyle preferences."""
    user = _user(1, lifestyle_raw=None)
    app = _app(user)

    with patch.object(users_route.CacheService, "delete", new_callable=AsyncMock):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/users/me",
                json={"lifestyle_preferences": {"diet": "Balanced", "sleep": "8h"}},
            )

    assert resp.status_code == 200
    assert resp.json()["lifestyle_preferences"]["diet"] == "Balanced"
    # In-memory ORM value is plaintext JSON string; EncryptedText encrypts on bind.
    assert json.loads(user.lifestyle_preferences)["diet"] == "Balanced"


# ── PROF006-03 / 04 ───────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_prof006_03_04_unauthenticated_rejected():
    """PROF006-03/04 — unauthenticated GET/PUT /me rejected."""
    app = _app(user=None)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        get_resp = await client.get("/api/v1/users/me")
        put_resp = await client.put(
            "/api/v1/users/me",
            json={"lifestyle_preferences": {"diet": "x"}},
        )
    assert get_resp.status_code in (401, 403)
    assert put_resp.status_code in (401, 403)


# ── PROF006-05 ────────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_prof006_05_client_user_id_ignored():
    """PROF006-05 — client-supplied user_id cannot override auth identity."""
    user = _user(1)
    app = _app(user)

    with patch.object(users_route.CacheService, "delete", new_callable=AsyncMock):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/users/me",
                json={
                    "user_id": 999,
                    "id": 999,
                    "lifestyle_preferences": {"diet": "Vegan"},
                },
            )

    assert resp.status_code == 200
    assert resp.json()["id"] == 1
    assert user.id == 1
    assert json.loads(user.lifestyle_preferences)["diet"] == "Vegan"


# ── PROF006-06 / 14 ───────────────────────────────────────────────────────────


def test_prof006_06_14_encrypted_storage_not_plaintext_duplicate():
    """PROF006-06/14 — EncryptedText bind encrypts; no plaintext column."""
    reset_fernet_for_tests()
    col = EncryptedText()
    plaintext = json.dumps({"diet": "Vegetarian", "smoking": "Never"})
    stored = col.process_bind_param(plaintext, dialect=None)
    assert stored is not None
    assert stored != plaintext
    assert "Vegetarian" not in stored
    assert "Never" not in stored
    roundtrip = col.process_result_value(stored, dialect=None)
    assert json.loads(roundtrip)["diet"] == "Vegetarian"
    # Model has a single EncryptedText column for lifestyle — no plaintext twin.
    from app.models.user import User

    assert "lifestyle_preferences" in User.__table__.c
    assert list(User.__table__.c.lifestyle_preferences.type.__class__.__mro__)
    assert User.__table__.c.lifestyle_preferences.type.__class__.__name__ == "EncryptedText"


# ── PROF006-09 / 10 ───────────────────────────────────────────────────────────


def test_prof006_09_10_invalid_and_oversized_rejected():
    """PROF006-09/10 — malformed / oversized lifestyle payloads rejected."""
    with pytest.raises(ValidationError):
        UserUpdate(lifestyle_preferences=["not", "an", "object"])
    with pytest.raises(ValidationError):
        UserUpdate(lifestyle_preferences={"diet": 123})
    with pytest.raises(ValidationError):
        UserUpdate(lifestyle_preferences={"diet": "x" * 201})
    huge = {f"k{i}": "v" for i in range(25)}
    with pytest.raises(ValidationError):
        UserUpdate(lifestyle_preferences=huge)


# ── PROF006-11 / 12 ───────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_prof006_11_12_no_cross_user_access_via_me():
    """PROF006-11/12 — /me always scopes to auth user; no foreign id path."""
    user_a = _user(1, lifestyle_raw=json.dumps({"diet": "A"}))
    app = _app(user_a)

    with patch.object(users_route.CacheService, "get", new_callable=AsyncMock, return_value=None), patch.object(
        users_route.CacheService, "set", new_callable=AsyncMock
    ), patch.object(users_route.CacheService, "delete", new_callable=AsyncMock):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # Even with spoofed query/body identity, response is user A's.
            get_resp = await client.get("/api/v1/users/me?user_id=2")
            put_resp = await client.put(
                "/api/v1/users/me",
                json={"user_id": 2, "lifestyle_preferences": {"diet": "Hijack"}},
            )

    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == 1
    assert get_resp.json()["lifestyle_preferences"]["diet"] == "A"
    assert put_resp.status_code == 200
    assert put_resp.json()["id"] == 1
    assert json.loads(user_a.lifestyle_preferences)["diet"] == "Hijack"
    # There is no /users/{id} lifestyle route in this module for cross-read.
    assert not any(
        getattr(r, "path", "").endswith("/{user_id}")
        for r in users_route.router.routes
    )


# ── PROF006-13 ────────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_prof006_13_plaintext_not_written_to_audit_logs(caplog):
    """PROF006-13 — audit log is metadata-only (no preference content)."""
    user = _user(1)
    app = _app(user)
    secret = "SecretDietPreferenceXYZ"

    with patch.object(users_route.CacheService, "delete", new_callable=AsyncMock), caplog.at_level(
        logging.INFO
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/users/me",
                json={"lifestyle_preferences": {"diet": secret}},
            )

    assert resp.status_code == 200
    joined = " ".join(r.getMessage() for r in caplog.records)
    assert secret not in joined
    assert "SecretDiet" not in joined
