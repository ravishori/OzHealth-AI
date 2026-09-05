import os
import logging
import traceback

# ── Logging must be configured FIRST, before any other imports ────────────────
from app.core.logging_config import setup_logging, audit_log, cleanup_old_logs
setup_logging()
cleanup_old_logs(retain_days=7)

from fastapi import FastAPI, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import settings
from app.core.database import engine, Base
from app.core.deps import get_current_user
from app.core.exceptions import AppException, RateLimitError
from app.core.request_context import get_correlation_id
from app.models.user import User
from app.middleware.logging_middleware import RequestLoggingMiddleware
from app.middleware.security_middleware import SecurityHeadersMiddleware
from app.middleware.correlation_middleware import CorrelationIdMiddleware
from app.services.alert_service import send_alert_email, log_error_to_db
from app.api.routes import (
    auth, users, family, records, prescriptions,
    medicines, reminders, health_metrics, ai_assistant, emergency, nearby,
    interactions, symptoms, lab_analysis, insights, eprescriptions,
)
from app.api.routes import errors as errors_route
from app.api.routes import medicine_cache as medicine_cache_route
from app.api.routes import enrichment    as enrichment_route

# Ensure models are imported so Base.metadata knows about their tables.
from app.models import medicine_search_cache    as _medicine_cache_model     # noqa: F401
from app.models import medicine_enrichment_log  as _medicine_enrichment_log  # noqa: F401
from app.models.error_log import ErrorLog as _error_log_model                # noqa: F401

# Backward-compatible aliases (used by auth.py inline import — kept for safety)
_send_alert_email = send_alert_email
_log_error_to_db  = log_error_to_db

logger = logging.getLogger(__name__)


# ─── App ──────────────────────────────────────────────────────────────────────

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description=(
        "HealthNest — personal health companion for Australia.\n\n"
        "**Features**: OTP auth, family health management, prescription OCR, "
        "TGA medicine search, AI health chat (Claude), medication reminders, "
        "emergency SOS, and nearby services via OpenStreetMap."
    ),
    contact={"name": "HealthNest Team"},
    license_info={"name": "Private"},
)

# ─── Middleware (order matters — outermost wraps first) ───────────────────────

# 1. GZip compression
app.add_middleware(GZipMiddleware, minimum_size=1000)

# 2. Security headers
app.add_middleware(SecurityHeadersMiddleware)

# 3. Request/response logging (reads correlation_id set in step 4)
app.add_middleware(RequestLoggingMiddleware)

# 4. Correlation ID — MUST be inner-most so it runs FIRST and sets the ID
#    before the logging middleware reads it.  Starlette executes middleware
#    in reverse-add order (last-added = first-executed for Starlette).
app.add_middleware(CorrelationIdMiddleware)

# 5. CORS — explicit origins only (never '*' with credentials)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.get_cors_origins(),
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

    cid = get_correlation_id()
    body: dict = {"error": exc.error_code, "message": exc.message}
    if cid:
        body["correlation_id"] = cid

    return JSONResponse(status_code=exc.status_code, content=body, headers=headers)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Handle Pydantic request validation errors with a clean response."""
    errors = [
        {"field": ".".join(str(loc) for loc in e["loc"]), "message": e["msg"]}
        for e in exc.errors()
    ]
    logger.info("Validation error on %s %s: %s", request.method, request.url.path, errors)
    cid = get_correlation_id()
    body = {"error": "VALIDATION_ERROR", "message": "Invalid request data", "details": errors}
    if cid:
        body["correlation_id"] = cid
    return JSONResponse(status_code=422, content=body)


@app.exception_handler(SQLAlchemyError)
async def db_exception_handler(request: Request, exc: SQLAlchemyError):
    """Handle database errors — log full details, return safe message to client."""
    tb_str = traceback.format_exc()
    client_ip = request.client.host if request.client else "unknown"
    cid = get_correlation_id()

    logger.error(
        "Database error on %s %s: %s",
        request.method, request.url.path, exc, exc_info=True,
    )
    await send_alert_email(
        subject="Database Error",
        source="backend",
        error_type=type(exc).__name__,
        message=str(exc),
        tb=tb_str,
        extra={
            "request":        f"{request.method} {request.url}",
            "client_ip":      client_ip,
            "correlation_id": cid,
        },
    )
    await log_error_to_db(
        source="backend",
        severity="critical",
        error_type=type(exc).__name__,
        message=str(exc),
        stack_trace=tb_str,
        http_method=request.method,
        request_path=request.url.path,
        client_ip=client_ip,
        correlation_id=cid,
    )

    body = {
        "error":   "DATABASE_ERROR",
        "message": "Something went wrong. Please try again later.",
    }
    if cid:
        body["correlation_id"] = cid
    return JSONResponse(status_code=503, content=body)


@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    """Catch-all handler — prevents stack traces leaking to clients."""
    tb_str = traceback.format_exc()
    client_ip = request.client.host if request.client else "unknown"
    cid = get_correlation_id()

    logger.error(
        "Unhandled exception on %s %s: %s",
        request.method, request.url.path, exc, exc_info=True,
    )
    await send_alert_email(
        subject="Unhandled Server Error (500)",
        source="backend",
        error_type=type(exc).__name__,
        message=str(exc),
        tb=tb_str,
        extra={
            "request":        f"{request.method} {request.url}",
            "client_ip":      client_ip,
            "user_agent":     request.headers.get("user-agent", "unknown"),
            "correlation_id": cid,
        },
    )
    await log_error_to_db(
        source="backend",
        severity="critical",
        error_type=type(exc).__name__,
        message=str(exc),
        stack_trace=tb_str,
        http_method=request.method,
        request_path=request.url.path,
        client_ip=client_ip,
        correlation_id=cid,
    )

    body = {
        "error":   "INTERNAL_ERROR",
        "message": "Something went wrong. Please try again later.",
    }
    if cid:
        body["correlation_id"] = cid
    return JSONResponse(status_code=500, content=body)

# Uploads directory exists for authenticated downloads via GET /api/v1/records/{id}/file.
# Do NOT mount a public StaticFiles path at /uploads (P0: PHI leakage).
os.makedirs(settings.LOCAL_UPLOAD_DIR, exist_ok=True)

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
app.include_router(interactions.router,   prefix=f"{PREFIX}/interactions",    tags=["Drug Interactions"])
app.include_router(symptoms.router,       prefix=f"{PREFIX}/symptoms",        tags=["Symptom Checker"])
app.include_router(lab_analysis.router,   prefix=f"{PREFIX}/lab-analysis",    tags=["Lab Report Analyzer"])
app.include_router(insights.router,         prefix=f"{PREFIX}/insights",         tags=["Health Insights"])
app.include_router(eprescriptions.router,  prefix=f"{PREFIX}/eprescriptions",   tags=["ePrescriptions"])
app.include_router(errors_route.router,    prefix=f"{PREFIX}/errors",           tags=["Error Reporting"])
app.include_router(medicine_cache_route.router, prefix=PREFIX,                  tags=["Medicine Cache"])
app.include_router(enrichment_route.router,     prefix=f"{PREFIX}/enrichment",  tags=["Medicine Enrichment"])


# ─── Startup / Shutdown ───────────────────────────────────────────────────────

@app.on_event("startup")
async def on_startup():
    # Auto-create tables (idempotent — safe to run every startup)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # Start background reminder scheduler
    from app.services.reminder_worker import start_scheduler
    start_scheduler()

    # Weekly log cleanup scheduler (Saturday 00:05 AEDT)
    from apscheduler.schedulers.asyncio import AsyncIOScheduler
    from apscheduler.triggers.cron import CronTrigger
    from app.core.logging_config import cleanup_old_logs

    log_scheduler = AsyncIOScheduler(timezone="Australia/Sydney")
    log_scheduler.add_job(
        cleanup_old_logs,
        CronTrigger(day_of_week="sat", hour=0, minute=5),
        kwargs={"retain_days": 7},
        id="weekly_log_cleanup",
        name="Weekly log cleanup (Saturday 00:05 AEDT)",
        replace_existing=True,
    )
    log_scheduler.start()
    app.state.log_scheduler = log_scheduler
    logger.info("Weekly log cleanup scheduler started (runs every Saturday 00:05 AEDT)")

    # Validate external service credentials
    from app.services.notification_service import validate_external_services
    validate_external_services()

    # Warm up Redis connection
    from app.services.cache_service import _get_redis
    await _get_redis()

    # Start nightly medicine-cache refresh worker (02:30 AEDT/AEST)
    from app.workers.cache_refresh_worker import start_scheduler as start_cache_worker
    app.state.cache_worker = start_cache_worker()

    logger.info("%s v%s started", settings.APP_NAME, settings.APP_VERSION)
    logger.info("API docs: http://localhost:8000/docs")
    audit_log.info("app_startup", extra={"version": settings.APP_VERSION})


@app.on_event("shutdown")
async def on_shutdown():
    from app.services.reminder_worker import stop_scheduler
    stop_scheduler()

    if hasattr(app.state, "log_scheduler"):
        app.state.log_scheduler.shutdown(wait=False)

    from app.workers.cache_refresh_worker import stop_scheduler as stop_cache_worker
    stop_cache_worker()

    logger.info("%s shut down", settings.APP_NAME)
    audit_log.info("app_shutdown", extra={"version": settings.APP_VERSION})


# ─── Health & Meta endpoints ──────────────────────────────────────────────────

@app.get("/", tags=["Meta"])
async def root():
    return {
        "app":        settings.APP_NAME,
        "version":    settings.APP_VERSION,
        "status":     "running",
        "docs":       "/docs",
        "api_prefix": PREFIX,
    }


@app.get("/health", tags=["Meta"])
async def health():
    """Liveness probe — returns 200 when the app is running."""
    return {"status": "healthy"}


@app.get(f"{PREFIX}/admin/stats", tags=["Admin"])
async def admin_stats(current_user: User = Depends(get_current_user)):
    """Platform statistics — restricted to DEVELOPER_EMAILS (empty list = deny all)."""
    from app.core.admin_auth import assert_admin_access

    assert_admin_access(current_user.email)

    from sqlalchemy import text
    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        result = await db.execute(text("SELECT * FROM fn_user_stats()"))  # nosec
        row = result.mappings().first()

    return dict(row) if row else {}
