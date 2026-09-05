"""Sprint 2 — admin stats authorization + CORS origin hardening."""
from __future__ import annotations

from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.core.admin_auth import assert_admin_access
from app.core.config import Settings


def test_admin_denied_when_developer_emails_empty():
    with patch("app.core.admin_auth.settings") as mock_settings:
        mock_settings.get_developer_emails.return_value = []
        with pytest.raises(HTTPException) as exc:
            assert_admin_access("anyone@example.com")
        assert exc.value.status_code == 403


def test_admin_denied_for_non_developer():
    with patch("app.core.admin_auth.settings") as mock_settings:
        mock_settings.get_developer_emails.return_value = ["admin@healthnest.au"]
        with pytest.raises(HTTPException) as exc:
            assert_admin_access("user@example.com")
        assert exc.value.status_code == 403


def test_admin_allowed_for_developer_case_insensitive():
    with patch("app.core.admin_auth.settings") as mock_settings:
        mock_settings.get_developer_emails.return_value = ["Admin@HealthNest.au"]
        assert_admin_access("admin@healthnest.au")  # must not raise


def test_cors_origins_never_wildcard():
    s = Settings(
        DATABASE_URL="postgresql+asyncpg://u:p@localhost/db",
        SYNC_DATABASE_URL="postgresql+psycopg2://u:p@localhost/db",
        SECRET_KEY="test-secret-key-for-unit-tests-only",
        CORS_ORIGINS='["*"]',
    )
    origins = s.get_cors_origins()
    assert "*" not in origins
    assert len(origins) >= 1


def test_cors_origins_parses_explicit_list():
    s = Settings(
        DATABASE_URL="postgresql+asyncpg://u:p@localhost/db",
        SYNC_DATABASE_URL="postgresql+psycopg2://u:p@localhost/db",
        SECRET_KEY="test-secret-key-for-unit-tests-only",
        CORS_ORIGINS='["https://app.example.com"]',
    )
    assert s.get_cors_origins() == ["https://app.example.com"]


def test_sos_response_never_claims_contacts_notified():
    """Contract: dial-first SOS must report contacts_notified=0."""
    from app.api.routes import emergency as emergency_route
    import inspect

    src = inspect.getsource(emergency_route.trigger_sos)
    assert "contacts_notified=0" in src
    assert "NOT automatically notified" in src or "dial-first" in src.lower()
