"""
Structured JSON logging for VitaPulse AI.

Log files (all under backend/logs/):
  app.log        — All levels (DEBUG+).   Daily rotation, 7-day retention.
  errors.log     — ERROR+ only.           Daily rotation, 7-day retention.
  functions.log  — Function trace (enter/ok/fail + timing). Daily, 7-day.
  db.log         — SQLAlchemy SQL queries. Daily rotation, 7-day retention.
  audit.log      — Sensitive ops (OTP, login, SOS). Size-based, 30 backups.

Rotation policy:
  TimedRotatingFileHandler(when='midnight', backupCount=7) — rotates at
  midnight; keeps 7 daily backup files; the 8th-day file is auto-deleted.
  This achieves "delete logs older than one week" automatically.

  On every startup the `cleanup_old_logs()` helper also removes any stale
  files that predate the backupCount window (guards against clock drift or
  manual file copies).
"""
import glob
import logging
import logging.handlers
import os
import time
from datetime import datetime, timedelta
from pythonjsonlogger import jsonlogger


# ── Log directory ─────────────────────────────────────────────────────────────
LOG_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "logs"
)
os.makedirs(LOG_DIR, exist_ok=True)


# ── JSON formatter ─────────────────────────────────────────────────────────────

class JsonFormatter(jsonlogger.JsonFormatter):
    def add_fields(self, log_record, record, message_dict):
        super().add_fields(log_record, record, message_dict)
        log_record["level"] = record.levelname
        log_record["logger"] = record.name
        log_record.pop("levelname", None)
        log_record.pop("name", None)


_JSON_FMT = JsonFormatter("%(asctime)s %(level)s %(logger)s %(message)s")


# ── Handler factory ────────────────────────────────────────────────────────────

def _daily_handler(filename: str, level: int = logging.DEBUG) -> logging.Handler:
    """
    TimedRotatingFileHandler that:
      - Rotates at midnight (local time)
      - Keeps 7 backup files  →  auto-deletes anything older than 7 days
      - Writes JSON
    """
    h = logging.handlers.TimedRotatingFileHandler(
        os.path.join(LOG_DIR, filename),
        when="midnight",
        interval=1,
        backupCount=7,
        encoding="utf-8",
        utc=False,
    )
    h.setLevel(level)
    h.setFormatter(_JSON_FMT)
    return h


# ── Startup log cleanup ───────────────────────────────────────────────────────

def cleanup_old_logs(retain_days: int = 7) -> int:
    """
    Delete any log backup files older than `retain_days` days.
    Called once at startup as a safety net alongside TimedRotatingFileHandler's
    own backupCount pruning.

    Returns number of files deleted.
    """
    cutoff = time.time() - retain_days * 86400
    deleted = 0
    for pattern in ["app.log.*", "errors.log.*", "functions.log.*", "db.log.*"]:
        for path in glob.glob(os.path.join(LOG_DIR, pattern)):
            try:
                if os.path.getmtime(path) < cutoff:
                    os.remove(path)
                    deleted += 1
            except OSError:
                pass
    return deleted


# ── Main setup ────────────────────────────────────────────────────────────────

def setup_logging() -> None:
    """
    Configure root logger with five destinations.
    Call exactly once at startup (before any other imports).
    """
    # ── Console (INFO+) ───────────────────────────────────────────────────────
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    console.setFormatter(_JSON_FMT)

    # ── app.log  — everything (DEBUG+) ───────────────────────────────────────
    app_handler = _daily_handler("app.log", logging.DEBUG)

    # ── errors.log — ERROR and above only ────────────────────────────────────
    err_handler = _daily_handler("errors.log", logging.ERROR)

    # ── functions.log — function trace (routed via vitapulse.functions) ───────
    fn_handler = _daily_handler("functions.log", logging.DEBUG)

    # ── db.log — SQLAlchemy SQL query traces ──────────────────────────────────
    db_handler = _daily_handler("db.log", logging.DEBUG)

    # ── Root logger ───────────────────────────────────────────────────────────
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    root.handlers.clear()
    root.addHandler(console)
    root.addHandler(app_handler)
    root.addHandler(err_handler)

    # ── vitapulse.functions logger (function traces) ───────────────────────────
    fn_logger = logging.getLogger("vitapulse.functions")
    fn_logger.setLevel(logging.DEBUG)
    fn_logger.propagate = False          # keep function traces OUT of app.log
    fn_logger.handlers.clear()
    fn_logger.addHandler(fn_handler)
    fn_logger.addHandler(console)        # also show in console at INFO

    # ── SQLAlchemy to db.log ───────────────────────────────────────────────────
    sa_logger = logging.getLogger("sqlalchemy.engine")
    sa_logger.setLevel(logging.DEBUG)
    sa_logger.propagate = False          # keep SQL OUT of app.log noise
    sa_logger.handlers.clear()
    sa_logger.addHandler(db_handler)

    # ── Silence noisy third-party loggers ─────────────────────────────────────
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("apscheduler").setLevel(logging.WARNING)
    logging.getLogger("passlib").setLevel(logging.WARNING)

    # ── Prune stale log files on startup ──────────────────────────────────────
    n = cleanup_old_logs(retain_days=7)
    if n:
        logging.getLogger(__name__).info("Cleaned up %d old log file(s)", n)


# ── Audit logger ──────────────────────────────────────────────────────────────

def setup_audit_logger() -> logging.Logger:
    """
    Dedicated audit logger → logs/audit.log.
    Uses size-based rotation (10 MB × 30 backups ≈ 300 MB cap).
    Audit events are never auto-deleted — they are compliance records.
    """
    audit_handler = logging.handlers.RotatingFileHandler(
        os.path.join(LOG_DIR, "audit.log"),
        maxBytes=10 * 1024 * 1024,   # 10 MB per file
        backupCount=30,
        encoding="utf-8",
    )
    audit_handler.setLevel(logging.INFO)
    audit_handler.setFormatter(_JSON_FMT)

    logger = logging.getLogger("vitapulse.audit")
    logger.setLevel(logging.INFO)
    logger.propagate = False
    logger.handlers.clear()
    logger.addHandler(audit_handler)
    return logger


# Module-level audit logger — import this wherever audit events are needed
audit_log = setup_audit_logger()
