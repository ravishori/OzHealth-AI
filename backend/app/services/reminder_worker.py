"""
Background worker that fires medication reminders every 5 minutes.

Uses APScheduler (AsyncIOScheduler). Integrated into FastAPI startup.

To run, APScheduler must be installed:
    pip install apscheduler
"""

import logging
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

_scheduler = None


async def _dispatch_reminders() -> None:
    """Query due reminders and send push notifications."""
    from app.core.database import AsyncSessionLocal
    from app.services.notification_service import NotificationService
    from sqlalchemy import text

    try:
        async with AsyncSessionLocal() as db:
            # Use the fn_get_due_reminders() PostgreSQL function (5-min window)
            result = await db.execute(
                text("SELECT * FROM fn_get_due_reminders(:window)"),
                {"window": 5},
            )
            rows = result.mappings().all()

        logger.info("[ReminderWorker] Checking reminders at %s — %d due",
                    datetime.now(timezone.utc).strftime("%H:%M"), len(rows))

        for row in rows:
            schedule = dict(row)
            success = await NotificationService.send_medication_reminder(schedule)
            if success:
                logger.debug("  ✓ Sent reminder for %s to user %s",
                             schedule.get("medicine_name"), schedule.get("user_id"))
    except Exception as exc:
        logger.error("[ReminderWorker] Error: %s", exc)


async def _dispatch_refill_alerts() -> None:
    """Daily job: alert users about upcoming refills or low stock."""
    from app.core.database import AsyncSessionLocal
    from app.services.notification_service import NotificationService
    from sqlalchemy import text

    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(text("SELECT * FROM v_refill_alerts"))
            rows = result.mappings().all()

        logger.info("[RefillWorker] Found %d refill alerts", len(rows))
        for row in rows:
            schedule = dict(row)
            if schedule.get("fcm_token"):
                await NotificationService.send_refill_alert(schedule)
    except Exception as exc:
        logger.error("[RefillWorker] Error: %s", exc)


def start_scheduler() -> None:
    """Initialise and start APScheduler. Call once from FastAPI startup."""
    global _scheduler
    try:
        from apscheduler.schedulers.asyncio import AsyncIOScheduler
        from apscheduler.triggers.cron import CronTrigger
        from apscheduler.triggers.interval import IntervalTrigger

        _scheduler = AsyncIOScheduler(timezone="Australia/Sydney")

        # Run every 5 minutes — dispatch medication reminders
        _scheduler.add_job(
            _dispatch_reminders,
            trigger=IntervalTrigger(minutes=5),
            id="medication_reminders",
            replace_existing=True,
        )

        # Run daily at 8:00 AM AEST — refill alerts
        _scheduler.add_job(
            _dispatch_refill_alerts,
            trigger=CronTrigger(hour=8, minute=0, timezone="Australia/Sydney"),
            id="refill_alerts",
            replace_existing=True,
        )

        _scheduler.start()
        logger.info("[ReminderWorker] APScheduler started (5-min reminders + 08:00 refill alerts)")
    except ImportError:
        logger.warning(
            "[ReminderWorker] APScheduler not installed — background reminders disabled. "
            "Install with: pip install apscheduler"
        )
    except Exception as exc:
        logger.error("[ReminderWorker] Failed to start scheduler: %s", exc)


def stop_scheduler() -> None:
    """Gracefully stop the scheduler. Call from FastAPI shutdown."""
    global _scheduler
    if _scheduler and _scheduler.running:
        _scheduler.shutdown(wait=False)
        logger.info("[ReminderWorker] Scheduler stopped.")
