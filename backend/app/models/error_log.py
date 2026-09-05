import os
import socket
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Text, DateTime
from app.core.database import Base

_ENVIRONMENT = os.getenv("ENV", "development")
_HOSTNAME    = socket.gethostname()


class ErrorLog(Base):
    """Persists every server-side unhandled exception and every client crash report."""

    __tablename__ = "error_logs"

    id           = Column(Integer, primary_key=True, autoincrement=True)

    # ── Source & classification ───────────────────────────────────────────────
    source       = Column(String(50),  nullable=False, default="backend")  # "backend" | "flutter"
    severity     = Column(String(20),  nullable=False, default="error")    # "info"|"warning"|"error"|"critical"
    error_type   = Column(String(200), nullable=True)
    message      = Column(Text,        nullable=False, default="")
    stack_trace  = Column(Text,        nullable=True)

    # ── Request context ───────────────────────────────────────────────────────
    http_method  = Column(String(10),  nullable=True)
    request_path = Column(String(500), nullable=True)
    correlation_id = Column(String(64), nullable=True)
    client_ip    = Column(String(50),  nullable=True)
    user_id      = Column(Integer,     nullable=True)

    # ── Client / device info ──────────────────────────────────────────────────
    platform     = Column(String(50),  nullable=True)
    app_version  = Column(String(50),  nullable=True)
    screen       = Column(String(200), nullable=True)
    context      = Column(String(200), nullable=True)

    # ── Server environment ────────────────────────────────────────────────────
    environment  = Column(String(50),  nullable=True, default=_ENVIRONMENT)
    hostname     = Column(String(200), nullable=True, default=_HOSTNAME)

    # ── Timestamp ─────────────────────────────────────────────────────────────
    created_at   = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
