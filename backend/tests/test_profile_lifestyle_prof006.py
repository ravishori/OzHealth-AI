"""HN-PROF-006 — lifestyle preferences GET/PUT on authenticated /users/me."""
from __future__ import annotations

import inspect
import json
import logging
import os
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import users as users_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.services.encryption_service import EncryptedText
from app.schemas.user import UserResponse, UserUpdate

MARKER = "PROF-LIFE-UNIQUE-VEGAN-HALAL-42"


def _user(uid: int = 1, **kwargs):
    defaults = dict(
        id=uid,
        name=f"User{uid}",
        email=f"u{uid}@example.com",
        phone=f"+6140000000{uid}",
        phone2=None,
        age=40,
        gender="Female",
        blood_group="O+",
        health_conditions='["Asthma"]',
        allergies='["Penicillin"]',
        lifestyle_preferences=json.dumps(
            {"diet": "Vegetarian", "exercise": "Walking"}
        ),
        suburb="Richmond",
        city="Melbourne",
        state="VIC",
        postcode="3121",
        profile_image_url=None,
        is_verified=True,
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
        fcm_token="SHOULD-NOT-APPEAR",
        token_version=1,
        is_active=True,
    )
    defaults.update(kwargs)
    return SimpleNamespace(**defaults)


@pytest.fixture
def anyio_backend():
    return "asyncio"


def _app(user):
    app = FastAPI()
    app.include_router(users_route.router, prefix="/api/v1/users")

    async def _override_user():
        return user

    async def _override_db():
        db = AsyncMock()
        yield db

    app.dependency_overrides[get_current_user] = _override_user
    app.dependency_overrides[get_db] = _override_db
    return app


def _cache_patches():
    return (
        patch.object(users_route.CacheService, "get", AsyncMock(return_value=None)),
        patch.object(users_route.CacheService, "set", AsyncMock()),
        patch.object(users_route.CacheService, "delete", AsyncMock()),
    )


async def _client_get_me(user):
    app = _app(user)
    g, s, d = _cache_patches()
    with g, s, d:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.get("/api/v1/users/me")


async def _client_put_me(user, payload):
    app = _app(user)
    g, s, d = _cache_patches()
    with g, s, d:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.put("/api/v1/users/me", json=payload)


def test_prof_life_encryption_reuses_encrypted_text():
    col = User.__table__.c.lifestyle_preferences
    assert isinstance(col.type, EncryptedText)
    assert col.nullable is True


@pytest.mark.anyio
async def test_prof_life_be_01_get_returns_persisted_lifestyle():
    """PROF-LIFE-BE-01 — Authenticated user GET returns persisted lifestyle preferences."""
    user = _user()
    resp = await _client_get_me(user)
    assert resp.status_code == 200
    body = resp.json()
    assert body["lifestyle_preferences"] == {
        "diet": "Vegetarian",
        "exercise": "Walking",
    }
    assert "fcm_token" not in body
    assert body["id"] == 1


@pytest.mark.anyio
async def test_prof_life_be_02_put_updates_lifestyle():
    """PROF-LIFE-BE-02 — Authenticated user can update lifestyle preferences."""
    user = _user()
    payload = {
        "lifestyle_preferences": {
            "diet": MARKER,
            "sleep": "7 hours",
        }
    }
    resp = await _client_put_me(user, payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["lifestyle_preferences"]["diet"] == MARKER
    assert body["lifestyle_preferences"]["sleep"] == "7 hours"
    stored = json.loads(user.lifestyle_preferences)
    assert stored["diet"] == MARKER


@pytest.mark.anyio
async def test_prof_life_be_03_put_then_get_round_trip():
    """PROF-LIFE-BE-03 — Updated values persist and are returned by GET."""
    user = _user()
    put_resp = await _client_put_me(
        user,
        {"lifestyle_preferences": {"alcohol": "None", "diet": "Halal"}},
    )
    assert put_resp.status_code == 200
    get_resp = await _client_get_me(user)
    assert get_resp.status_code == 200
    prefs = get_resp.json()["lifestyle_preferences"]
    assert prefs == {"alcohol": "None", "diet": "Halal"}


@pytest.mark.anyio
async def test_prof_life_be_04_null_empty_semantics():
    """PROF-LIFE-BE-04 — Null/empty behavior follows existing schema semantics."""
    user = _user(lifestyle_preferences=None)
    get_none = await _client_get_me(user)
    assert get_none.status_code == 200
    assert get_none.json()["lifestyle_preferences"] == {}

    user_empty = _user(lifestyle_preferences="{}")
    get_empty = await _client_get_me(user_empty)
    assert get_empty.json()["lifestyle_preferences"] == {}

    user_list = _user(lifestyle_preferences="[]")
    get_list = await _client_get_me(user_list)
    assert get_list.json()["lifestyle_preferences"] == {}

    original = json.dumps({"diet": "KeepMe"})
    user_skip = _user(lifestyle_preferences=original)
    # JSON null → UserUpdate field is None → existing write path skips the column.
    skip = await _client_put_me(user_skip, {"lifestyle_preferences": None, "age": 41})
    assert skip.status_code == 200
    assert json.loads(user_skip.lifestyle_preferences) == {"diet": "KeepMe"}
    assert user_skip.age == 41

    user_clear = _user()
    cleared = await _client_put_me(user_clear, {"lifestyle_preferences": {}})
    assert cleared.status_code == 200
    assert cleared.json()["lifestyle_preferences"] == {}
    assert json.loads(user_clear.lifestyle_preferences) == {}


@pytest.mark.anyio
async def test_prof_life_be_05_cannot_modify_another_user():
    """PROF-LIFE-BE-05 — Authenticated user cannot modify another user's profile."""
    owner = _user(1, lifestyle_preferences=json.dumps({"diet": "OwnerDiet"}))
    other = _user(2, lifestyle_preferences=json.dumps({"diet": "OtherDiet"}))

    resp = await _client_put_me(
        owner, {"lifestyle_preferences": {"diet": "ChangedByOwner"}}
    )
    assert resp.status_code == 200
    assert json.loads(other.lifestyle_preferences) == {"diet": "OtherDiet"}
    assert json.loads(owner.lifestyle_preferences) == {"diet": "ChangedByOwner"}

    app = _app(owner)
    g, s, d = _cache_patches()
    with g, s, d:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            by_id = await client.put(
                "/api/v1/users/2",
                json={"lifestyle_preferences": {"diet": "Hijack"}},
            )
            get_other = await client.get("/api/v1/users/2")
    assert by_id.status_code in (404, 405)
    assert get_other.status_code in (404, 405)
    assert json.loads(other.lifestyle_preferences) == {"diet": "OtherDiet"}


@pytest.mark.anyio
async def test_prof_life_be_06_client_user_id_cannot_override_owner():
    """PROF-LIFE-BE-06 — Client-supplied user_id/owner_id cannot override ownership."""
    user = _user(1)
    other = _user(2, lifestyle_preferences=json.dumps({"diet": "Untouched"}))
    resp = await _client_put_me(
        user,
        {
            "user_id": 2,
            "owner_id": 2,
            "id": 2,
            "lifestyle_preferences": {"diet": "StillUser1"},
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == 1
    assert body["lifestyle_preferences"]["diet"] == "StillUser1"
    assert json.loads(user.lifestyle_preferences)["diet"] == "StillUser1"
    assert json.loads(other.lifestyle_preferences)["diet"] == "Untouched"
    parsed = UserUpdate.model_validate(
        {"user_id": 99, "owner_id": 99, "lifestyle_preferences": {"diet": "x"}}
    )
    dumped = parsed.model_dump()
    assert "user_id" not in dumped
    assert "owner_id" not in dumped


@pytest.mark.anyio
async def test_prof_life_be_07_other_profile_fields_unaffected():
    """PROF-LIFE-BE-07 — Existing profile fields remain unaffected."""
    user = _user()
    resp = await _client_put_me(
        user, {"lifestyle_preferences": {"exercise": "Cycling"}}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "User1"
    assert body["age"] == 40
    assert body["gender"] == "Female"
    assert body["blood_group"] == "O+"
    assert body["health_conditions"] == ["Asthma"]
    assert body["allergies"] == ["Penicillin"]
    assert body["suburb"] == "Richmond"
    assert body["email"] == "u1@example.com"
    assert "fcm_token" not in body
    assert json.loads(user.health_conditions) == ["Asthma"]
    assert json.loads(user.allergies) == ["Penicillin"]
    assert user.name == "User1"


@pytest.mark.anyio
async def test_prof_life_be_08_raw_values_not_logged(caplog):
    """PROF-LIFE-BE-08 — Raw lifestyle preference values are not emitted into logs."""
    src = inspect.getsource(users_route.update_profile)
    assert "profile_updated" in src
    assert 'extra={"user_id": current_user.id}' in src
    after_audit = src.split("audit_log.info")[1]
    assert "lifestyle_preferences" not in after_audit
    assert MARKER not in src

    response_src = inspect.getsource(users_route._user_to_response)
    assert "logger" not in response_src

    user = _user()
    with caplog.at_level(logging.DEBUG):
        resp = await _client_put_me(
            user, {"lifestyle_preferences": {"diet": MARKER}}
        )
    assert resp.status_code == 200
    assert MARKER not in caplog.text

    schema = UserResponse.model_json_schema()
    assert "lifestyle_preferences" in schema["properties"]
    assert "fcm_token" not in schema["properties"]
