"""
Structured JSON logging for HealthNest.

Log files (all under backend/logs/):
  app.log          â€” All levels (DEBUG+).   Daily rotation, 7-day retention.
  errors.log       â€” ERROR+ only.           Daily rotation, 7-day retention.
  functions.log    â€” Function trace (enter/ok/fail + timing). Daily, 7-day.
  db.log           â€” SQLAlchemy SQL queries. Daily rotation, 7-day retention.
  audit.log        â€” Sensitive ops (OTP, login, SOS). Size-based, 30 backups.
  security.log     â€” Auth events, failed logins, rate-limit signals. 30-day.
  performance.log  â€” Slow requests (>2s), slow queries. Daily, 7-day.
  ai.log           â€” Claude API calls, token usage, AI errors. Daily, 7-day.
  ocr.log          â€” OCR operations, extraction errors. Daily, 7-day.

Rotation policy:
  TimedRotatingFileHandler(when='midnight', backupCount=N) â€” rotates at
  midnight; keeps N daily backup files.

Every JSON log line automatically includes:
  level, logger, environment, hostname, pid, correlation_id (when in-request)
"""
import glob
import logging
import logging.handlers
import os
import socket
import time
from pythonjsonlogger import jsonlogger


# â”€â”€ Environment / Machine constants (set once at import time) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
_ENVIRONMENT: str = os.getenv("ENV", "development")
_HOSTNAME:    str = socket.gethostname()
_PID:         int = os.getpid()

# â”€â”€ Log directory â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
LOG_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "logs"
)
os.makedirs(LOG_DIR, exist_ok=True)


# â”€â”€ JSON formatter â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class JsonFormatter(jsonlogger.JsonFormatter):
    """
    Extends python-json-logger to automatically include environment, hostname,
    pid, and the per-request correlation_id (read from contextvars when set by
    CorrelationIdMiddleware).
    """

    def add_fields(self, log_record, record, message_dict):
        super().add_fields(log_record, record, message_dict)
        log_record["level"]       = record.levelname
        log_record["logger"]      = record.name
        log_record["environment"] = _ENVIRONMENT
        log_record["hostname"]    = _HOSTNAME
        log_record["pid"]         = _PID

        # Inject correlation_id from the active request context â€” best-effort
        # (returns '' when called outside a request, e.g. startup or workers)
        if not log_record.get("correlation_id"):
            try:
                from app.core.request_context import get_correlation_id
                cid = get_correlation_id()
                if cid:
                    log_record["correlation_id"] = cid
            except Exception:
                pass

        log_record.pop("levelname", None)
        log_record.pop("name", None)


_JSON_FMT = JsonFormatter("%(asctime)s %(level)s %(logger)s %(message)s")


# â”€â”€ Handler factory â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

def _daily_handler(
    filename: str,
    level: int = logging.DEBUG,
    backup_count: int = 7,
) -> logging.Handler:
    """
    TimedRotatingFileHandler that:
      - Rotates at midnight (local time)
      - Keeps `backup_count` daily backup files
      - Writes JSON via _JSON_FMT
    """
    h = logging.handlers.TimedRotatingFileHandler(
        os.path.join(LOG_DIR, filename),
        when="midnight",
        interval=1,
        backupCount=backup_count,
        encoding="utf-8",
        utc=False,
    )
    h.setLevel(level)
    h.setFormatter(_JSON_FMT)
    return h


# â”€â”€ Startup log cleanup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

def cleanup_old_logs(retain_days: int = 7) -> int:
    """
    Delete any log backup files older than `retain_days` days.
    Called once at startup as a safety net alongside TimedRotatingFileHandler's
    own backupCount pruning.

    NOTE: security.log.* is intentionally excluded â€” audit/security records
    are kept for 30 days and managed by the handler's own backupCount.

    Returns number of files deleted.
    """
    cutoff = time.time() - retain_days * 86400
    deleted = 0
    patterns = [
        "app.log.*",
        "errors.log.*",
        "functions.log.*",
        "db.log.*",
        "performance.log.*",
        "ai.log.*",
        "ocr.log.*",
    ]
    for pattern in patterns:
        for path in glob.glob(os.path.join(LOG_DIR, pattern)):
            try:
                if os.path.getmtime(path) < cutoff:
                    os.remove(path)
                    deleted += 1
            except OSError:
                pass
    return deleted


# â”€â”€ Main setup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

def setup_logging() -> None:
    """
    Configure root logger and all named loggers with their destinations.
    Call exactly once at startup (before any other imports).
    """
    # â”€â”€ Console (INFO+) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    console.setFormatter(_JSON_FMT)

    # â”€â”€ app.log  â€” everything (DEBUG+) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    app_handler = _daily_handler("app.log", logging.DEBUG)

    # â”€â”€ errors.log â€” ERROR and above only â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    err_handler = _daily_handler("errors.log", logging.ERROR)

    # â”€â”€ functions.log â€” function trace (routed via vitapulse.functions) â”€â”€â”€â”€â”€â”€â”€
    fn_handler = _daily_handler("functions.log", logging.DEBUG)

    # â”€â”€ db.log â€” SQLAlchemy SQL query traces â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    db_handler = _daily_handler("db.log", logging.DEBUG)

    # â”€â”€ security.log â€” auth events, failed logins, rate-limit hits (30-day) â”€â”€â”€
    sec_handler = _daily_handler("security.log", logging.INFO, backup_count=30)

    # â”€â”€ performance.log â€” slow requests / slow queries â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    perf_handler = _daily_handler("performance.log", logging.DEBUG)

    # â”€â”€ ai.log â€” Claude API calls and errors â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ai_handler = _daily_handler("ai.log", logging.DEBUG)

    # â”€â”€ ocr.log â€” OCR operations and errors â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ocr_handler = _daily_handler("ocr.log", logging.DEBUG)

    # â”€â”€ Root logger â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    root.handlers.clear()
    root.addHandler(console)
    root.addHandler(app_handler)
    root.addHandler(err_handler)

    # â”€â”€ vitapulse.functions logger (function traces) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    fn_logger = logging.getLogger("vitapulse.functions")
    fn_logger.setLevel(logging.DEBUG)
    fn_logger.propagate = False          # keep function traces OUT of app.log
    fn_logger.handlers.clear()
    fn_logger.addHandler(fn_handler)
    fn_logger.addHandler(console)        # also show in console at INFO

    # â”€â”€ SQLAlchemy to db.log â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    sa_logger = logging.getLogger("sqlalchemy.engine")
    sa_logger.setLevel(logging.DEBUG)
    sa_logger.propagate = False          # keep SQL OUT of app.log noise
    sa_logger.handlers.clear()
    sa_logger.addHandler(db_handler)

    # â”€â”€ vitapulse.security â€” security events â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    sec_logger = logging.getLogger("vitapulse.security")
    sec_logger.setLevel(logging.INFO)
    sec_logger.propagate = False
    sec_logger.handlers.clear()
    sec_logger.addHandler(sec_handler)
    sec_logger.addHandler(console)

    # â”€â”€ vitapulse.performance â€” performance monitoring â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    perf_logger = logging.getLogger("vitapulse.performance")
    perf_logger.setLevel(logging.DEBUG)
    perf_logger.propagate = False
    perf_logger.handlers.clear()
    perf_logger.addHandler(perf_handler)
    perf_logger.addHandler(console)

    # â”€â”€ vitapulse.ai â€” Claude / AI service events â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ai_logger = logging.getLogger("vitapulse.ai")
    ai_logger.setLevel(logging.DEBUG)
    ai_logger.propagate = False
    ai_logger.handlers.clear()
    ai_logger.addHandler(ai_handler)
    ai_logger.addHandler(console)

    # â”€â”€ vitapulse.ocr â€” OCR service events â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ocr_logger = logging.getLogger("vitapulse.ocr")
    ocr_logger.setLevel(logging.DEBUG)
    ocr_logger.propagate = False
    ocr_logger.handlers.clear()
    ocr_logger.addHandler(ocr_handler)
    ocr_logger.addHandler(console)

    # â”€â”€ Silence noisy third-party loggers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("apscheduler").setLevel(logging.WARNING)
    logging.getLogger("passlib").setLevel(logging.WARNING)

    # â”€â”€ Prune stale log files on startup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    n = cleanup_old_logs(retain_days=7)
    if n:
        logging.getLogger(__name__).info("Cleaned up %d old log file(s)", n)


# â”€â”€ Audit logger â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

def setup_audit_logger() -> logging.Logger:
    """
    Dedicated audit logger â†’ logs/audit.log.
    Uses size-based rotation (10 MB Ã— 30 backups â‰ˆ 300 MB cap).
    Audit events are compliance records â€” never auto-deleted.
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


# â”€â”€ Module-level named loggers â€” import wherever needed â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

audit_log    = setup_audit_logger()
security_log = logging.getLogger("vitapulse.security")
perf_log     = logging.getLogger("vitapulse.performance")
ai_log       = logging.getLogger("vitapulse.ai")
ocr_log      = logging.getLogger("vitapulse.ocr")
