"""Admin authorization helpers for ops endpoints."""
from __future__ import annotations

from fastapi import HTTPException

from app.core.config import settings


def assert_admin_access(email: str | None) -> None:
    """Require caller's email to be listed in DEVELOPER_EMAILS.

    Empty DEVELOPER_EMAILS denies all callers (fail closed).
    """
    allowed = {e.lower() for e in settings.get_developer_emails()}
    normalized = (email or "").strip().lower()
    if not allowed or normalized not in allowed:
        raise HTTPException(status_code=403, detail="Admin access required")
