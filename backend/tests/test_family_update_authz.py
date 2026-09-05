"""HN-FAMILY-002 — family member update authorization (owner-scoped)."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.api.routes import family as family_route
from app.core.deps import get_current_user
from app.core.database import get_db


def _user(uid: int, email: str = "a@example.com"):
    return SimpleNamespace(id=uid, email=email, is_active=True)


def _member(
    mid: int = 10,
    owner_id: int = 1,
    name: str = "Alex",
    relationship: str = "Child",
    age: int = 12,
):
    from datetime import datetime, timezone

    m = SimpleNamespace(
        id=mid,
        user_id=owner_id,
        name=name,
        relationship=relationship,
        age=age,
        gender="Male",
        blood_group="O+",
        medical_conditions='["Asthma"]',
        allergies="[]",
        notes=None,
        created_at=datetime.now(timezone.utc),
        is_active=True,
    )
    return m


@pytest.fixture
def app_factory():
    def _make(user):
        app = FastAPI()
        app.include_router(family_route.router, prefix="/api/v1/family")

        async def _override_user():
            return user

        async def _override_db():
            db = AsyncMock()
            yield db

        app.dependency_overrides[get_current_user] = _override_user
        app.dependency_overrides[get_db] = _override_db
        return app

    return _make


@pytest.mark.anyio
async def test_owner_can_update_family_member(app_factory):
    owner = _user(1)
    app = app_factory(owner)
    member = _member(owner_id=1)

    with patch.object(
        family_route, "_get_member", AsyncMock(return_value=member)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/family/10",
                json={"name": "Alex Updated", "relationship": "Child"},
            )
        assert resp.status_code == 200
        assert resp.json()["name"] == "Alex Updated"
        assert member.name == "Alex Updated"


@pytest.mark.anyio
async def test_other_user_cannot_update_family_member(app_factory):
    other = _user(2, "b@example.com")
    app = app_factory(other)

    with patch.object(
        family_route,
        "_get_member",
        AsyncMock(
            side_effect=HTTPException(
                status_code=404, detail="Family member not found"
            )
        ),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.put(
                "/api/v1/family/10",
                json={"name": "Hacked"},
            )
        assert resp.status_code == 404


@pytest.mark.anyio
async def test_unauthenticated_family_update_rejected():
    app = FastAPI()
    app.include_router(family_route.router, prefix="/api/v1/family")

    async def _override_db():
        db = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = _override_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.put("/api/v1/family/10", json={"name": "X"})
    # Depends(get_current_user) without override → 401/403 depending on deps
    assert resp.status_code in (401, 403, 422)


@pytest.mark.anyio
async def test_get_member_filters_by_owner():
    """_get_member must require matching user_id (owner scope)."""
    import inspect

    src = inspect.getsource(family_route._get_member)
    assert "FamilyMember.user_id == user_id" in src
    assert "Family member not found" in src
