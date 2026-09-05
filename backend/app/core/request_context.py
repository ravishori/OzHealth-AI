"""
Request-scoped context values shared across async request handling.

Uses Python's built-in contextvars so values are automatically isolated
per asyncio Task — no threading or locking required.  In asyncio, awaiting
a coroutine runs it in the same context as the caller, so any value set in
the CorrelationIdMiddleware is visible to route handlers and every service
call they make.

Usage
-----
    # In middleware — called once per request:
    set_correlation_id(cid)

    # Anywhere in the same request context:
    cid = get_correlation_id()
"""
import uuid
from contextvars import ContextVar

_correlation_id: ContextVar[str] = ContextVar("correlation_id", default="")


def get_correlation_id() -> str:
    """Return the correlation ID for the current request context, or '' if unset."""
    return _correlation_id.get()


def set_correlation_id(cid: str) -> None:
    """Store a correlation ID for the duration of the current request context."""
    _correlation_id.set(cid)


def new_correlation_id() -> str:
    """Generate a fresh 32-char hex UUID4 string."""
    return uuid.uuid4().hex
