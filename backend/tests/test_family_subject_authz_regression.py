"""HN-FAMILY-010 — regression: family subject is client-side only.

Server authorization remains owner-scoped via existing
`_require_owned_active_family_member` helpers. There is no mutable
server-side "active subject" session.
"""
from __future__ import annotations

import os
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import health_metrics as health_route
from app.core.deps import get_current_user
from app.core.database import get_db


def _user(uid: int = 1):
    return SimpleNamespace(id=uid, email=f"u{uid}@example.com", is_active=True)


@pytest.fixture
def health_app():
    def _make(user):
        app = FastAPI()
        app.include_router(health_route.router, prefix="/api/v1/health-metrics")

        async def _override_user():
            return user

        app.dependency_overrides[get_current_user] = _override_user
        return app, user

    return _make


@pytest.mark.anyio
async def test_family_subject_09_unowned_family_member_rejected(health_app):
    """FAMILY-SUBJECT-09: owner-scoped authz still 404s unowned ids."""
    user = _user(1)
    app, _ = health_app(user)

    db = AsyncMock()
    result = MagicMock()
    result.scalar_one_or_none.return_value = None
    db.execute = AsyncMock(return_value=result)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get(
            "/api/v1/health-metrics/",
            params={"family_member_id": 999},
        )
    assert resp.status_code == 404


@pytest.mark.anyio
async def test_family_subject_09_no_server_subject_endpoint():
    """FAMILY-SUBJECT-09: no global server subject mutation route."""
    from app.api.routes import family as family_route

    paths = []
    for route in family_route.router.routes:
        path = getattr(route, "path", "")
        paths.append(path)
    joined = " ".join(paths).lower()
    assert "active-subject" not in joined
    assert "acting-as" not in joined
    assert "impersonat" not in joined


def test_family_subject_09_require_helper_exists():
    """Ownership helper remains the authz gate for family-scoped metrics."""
    assert hasattr(health_route, "_require_owned_active_family_member")
