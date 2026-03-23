import os
import logging
import smtplib
import traceback
from datetime import datetime, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

# ── Logging must be configured FIRST, before any other imports ────────────────
from app.core.logging_config import setup_logging, audit_log, cleanup_old_logs
setup_logging()
cleanup_old_logs(retain_days=7)   # purge log backups older than 7 days at startup

from fastapi import FastAPI, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import settings
from app.core.database import engine, Base
from app.core.deps import get_current_user
from app.core.exceptions import AppException, RateLimitError
from app.models.user import User
from app.middleware.logging_middleware import RequestLoggingMiddleware
from app.middleware.security_middleware import SecurityHeadersMiddleware
from app.api.routes import (
    auth, users, family, records, prescriptions,
    medicines, reminders, health_metrics, ai_assistant, emergency, nearby,
)

logger = logging.getLogger(__name__)


# ─── Alert email helper ───────────────────────────────────────────────────────

def _send_alert_email(subject: str, body: str) -> None:
    """
    Send a plain-text alert email to SMTP_EMAIL (self-notification).
    Fire-and-forget — never raises so it can't break request handling.
    Only runs when SMTP credentials are configured.
    """
    try:
        if not settings.SMTP_EMAIL or not settings.SMTP_PASSWORD:
            return  # SMTP not configured — skip silently

        msg = MIMEMultipart("alternative")
        msg["Subject"] = f"[{settings.APP_NAME}] {subject}"
        msg["From"] = settings.SMTP_EMAIL
        msg["To"] = settings.SMTP_EMAIL  # alert goes back to the developer

        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        full_body = f"{body}\n\nTimestamp: {timestamp}\nEnvironment: {os.getenv('ENV', 'development')}"
        msg.attach(MIMEText(full_body, "plain"))

        with smtplib.SMTP(settings.SMTP_SERVER, settings.SMTP_PORT, timeout=10) as server:
            server.ehlo()
            server.starttls()
            server.login(settings.SMTP_EMAIL, settings.SMTP_PASSWORD)
            server.sendmail(settings.SMTP_EMAIL, settings.SMTP_EMAIL, msg.as_string())

        logger.info("Alert email sent: %s", subject)
    except Exception as exc:
        logger.warning("Alert email failed (non-critical): %s", exc)


# ─── App ──────────────────────────────────────────────────────────────────────

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description=(
        "VitaPulse AI — AI-powered personal health companion for Australia.\n\n"
        "**Features**: OTP auth, family health management, prescription OCR, "
        "TGA medicine search, AI health chat (Claude), medication reminders, "
        "emergency SOS, and nearby services via OpenStreetMap."
    ),
    contact={"name": "VitaPulse AI Team"},
    license_info={"name": "Private"},
)

# ─── Middleware (order matters — outermost first) ─────────────────────────────

# 1. GZip compression (compress responses > 1KB)
app.add_middleware(GZipMiddleware, minimum_size=1000)

# 2. Security headers
app.add_middleware(SecurityHeadersMiddleware)

# 3. Request/response logging
app.add_middleware(RequestLoggingMiddleware)

# 4. CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # tighten in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Global Exception Handlers ────────────────────────────────────────────────

@app.exception_handler(AppException)
async def app_exception_handler(request: Request, exc: AppException):
    """Handle all custom AppException subclasses (AuthError, RateLimitError, etc.)."""
    headers = {}
    if isinstance(exc, RateLimitError):
        headers["Retry-After"] = str(exc.retry_after)

    if isinstance(exc, RateLimitError):
        logger.warning(
            "RATE_LIMIT [%s] %s %s — retry_after=%ss: %s",
            exc.error_code, request.method, request.url.path,
            exc.retry_after, exc.message,
        )
    else:
        logger.warning(
            "AppException [%s] %s %s: %s",
            exc.error_code, request.method, request.url.path, exc.message,
        )
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.error_code, "message": exc.message},
        headers=headers,
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Handle Pydantic request validation errors with a clean response."""
    errors = [
        {"field": ".".join(str(loc) for loc in e["loc"]), "message": e["msg"]}
        for e in exc.errors()
    ]
    logger.info("Validation error on %s %s: %s", request.method, request.url.path, errors)
    return JSONResponse(
        status_code=422,
        content={"error": "VALIDATION_ERROR", "message": "Invalid request data", "details": errors},
    )


@app.exception_handler(SQLAlchemyError)
async def db_exception_handler(request: Request, exc: SQLAlchemyError):
    """Handle database errors — log full details, return safe message to client."""
    logger.error(
        "Database error on %s %s: %s",
        request.method, request.url.path, exc, exc_info=True,
    )
    _send_alert_email(
        subject="🔴 Database Error",
        body=(
            f"A database error occurred.\n\n"
            f"Request: {request.method} {request.url}\n"
            f"Error: {exc}\n\n"
            f"Traceback:\n{traceback.format_exc()}"
        ),
    )
    return JSONResponse(
        status_code=503,
        content={"error": "DATABASE_ERROR", "message": "A database error occurred. Please try again."},
    )


@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    """Catch-all handler — prevents stack traces leaking to clients."""
    logger.error(
        "Unhandled exception on %s %s: %s",
        request.method, request.url.path, exc, exc_info=True,
    )
    _send_alert_email(
        subject="🔴 Unhandled Server Error (500)",
        body=(
            f"An unhandled exception occurred.\n\n"
            f"Request: {request.method} {request.url}\n"
            f"Error type: {type(exc).__name__}\n"
            f"Error: {exc}\n\n"
            f"Traceback:\n{traceback.format_exc()}"
        ),
    )
    return JSONResponse(
        status_code=500,
        content={"error": "INTERNAL_ERROR", "message": "An unexpected error occurred."},
    )

# ─── Static file serving for uploads ─────────────────────────────────────────

os.makedirs(settings.LOCAL_UPLOAD_DIR, exist_ok=True)
app.mount(
    "/uploads",
    StaticFiles(directory=settings.LOCAL_UPLOAD_DIR),
    name="uploads",
)

# ─── API Routes ───────────────────────────────────────────────────────────────

PREFIX = "/api/v1"

app.include_router(auth.router,           prefix=f"{PREFIX}/auth",           tags=["Auth"])
app.include_router(users.router,          prefix=f"{PREFIX}/users",           tags=["Users"])
app.include_router(family.router,         prefix=f"{PREFIX}/family",          tags=["Family"])
app.include_router(records.router,        prefix=f"{PREFIX}/records",         tags=["Medical Records"])
app.include_router(prescriptions.router,  prefix=f"{PREFIX}/prescriptions",   tags=["Prescriptions"])
app.include_router(medicines.router,      prefix=f"{PREFIX}/medicines",       tags=["Medicines"])
app.include_router(reminders.router,      prefix=f"{PREFIX}/reminders",       tags=["Reminders"])
app.include_router(health_metrics.router, prefix=f"{PREFIX}/health-metrics",  tags=["Health Metrics"])
app.include_router(ai_assistant.router,   prefix=f"{PREFIX}/ai",              tags=["AI Assistant"])
app.include_router(emergency.router,      prefix=f"{PREFIX}/emergency",       tags=["Emergency"])
app.include_router(nearby.router,         prefix=f"{PREFIX}/nearby",          tags=["Nearby Services"])


# ─── Startup / Shutdown ───────────────────────────────────────────────────────

@app.on_event("startup")
async def on_startup():
    # Auto-create tables (idempotent — safe to run every startup)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # Start background reminder scheduler
    from app.services.reminder_worker import start_scheduler
    start_scheduler()

    # Validate external service credentials (warn if missing)
    from app.services.notification_service import validate_external_services
    validate_external_services()

    # Warm up Redis connection
    from app.services.cache_service import _get_redis
    await _get_redis()

    logger.info("%s v%s started", settings.APP_NAME, settings.APP_VERSION)
    logger.info("API docs: http://localhost:8000/docs")
    audit_log.info("app_startup", extra={"version": settings.APP_VERSION})


@app.on_event("shutdown")
async def on_shutdown():
    from app.services.reminder_worker import stop_scheduler
    stop_scheduler()
    logger.info("%s shut down", settings.APP_NAME)
    audit_log.info("app_shutdown", extra={"version": settings.APP_VERSION})


# ─── Health & Meta endpoints ──────────────────────────────────────────────────

@app.get("/", tags=["Meta"])
async def root():
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "running",
        "docs": "/docs",
        "api_prefix": PREFIX,
    }


@app.get("/health", tags=["Meta"])
async def health():
    """Liveness probe — returns 200 when the app is running."""
    return {"status": "healthy"}


@app.get(f"{PREFIX}/admin/stats", tags=["Admin"])
async def admin_stats(
    current_user: User = Depends(get_current_user),
):
    """High-level platform statistics (authenticated)."""
    from sqlalchemy import text
    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        result = await db.execute(text("SELECT * FROM fn_user_stats()"))  # nosec — stored proc, no user input
        row = result.mappings().first()

    return dict(row) if row else {}
