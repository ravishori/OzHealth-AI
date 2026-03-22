from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os
import logging

from app.core.config import settings
from app.core.database import engine, Base
from app.core.deps import get_current_user
from app.models.user import User
from app.api.routes import (
    auth, users, family, records, prescriptions,
    medicines, reminders, health_metrics, ai_assistant, emergency, nearby,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger(__name__)

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

# ─── CORS ─────────────────────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # tighten in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
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

    logger.info("✅ %s v%s started", settings.APP_NAME, settings.APP_VERSION)
    logger.info("📖 API docs: http://localhost:8000/docs")


@app.on_event("shutdown")
async def on_shutdown():
    from app.services.reminder_worker import stop_scheduler
    stop_scheduler()
    logger.info("🛑 %s shut down", settings.APP_NAME)


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
    """
    High-level platform statistics.
    Available to all authenticated users (scope can be restricted later).
    """
    from sqlalchemy import text
    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        result = await db.execute(text("SELECT * FROM fn_user_stats()"))
        row = result.mappings().first()

    return dict(row) if row else {}
