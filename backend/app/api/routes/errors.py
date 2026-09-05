"""
Flutter client-side error reporting endpoint.

POST /api/v1/errors/report
  — Accepts crash reports from the Flutter app (no auth required so it works
    even when the user session has expired or the error happens before login).
  — Rate-limited per IP: max 20 reports per 5 minutes (guards against floods).
  — Fires an alert email to all developer recipients.
  — Persists to the error_logs table for DB-level audit.
  — Always returns 200 so the Flutter client never retries on HTTP error.
"""
import logging
from fastapi import APIRouter, Request
from pydantic import BaseModel
from typing import Optional

from app.core.log_decorator import LoggedAPIRoute
from app.services.cache_service import CacheService
from app.services.alert_service import send_alert_email, log_error_to_db

router = APIRouter(route_class=LoggedAPIRoute)
logger = logging.getLogger(__name__)

_RATE_LIMIT  = 20
_RATE_WINDOW = 300  # seconds


class ClientErrorReport(BaseModel):
    source: str = "flutter"
    context: Optional[str] = None
    error_type: Optional[str] = None
    message: str
    stack_trace: Optional[str] = None
    platform: Optional[str] = None
    app_version: Optional[str] = None
    user_id: Optional[int] = None
    screen: Optional[str] = None
    timestamp: Optional[str] = None


@router.post("/report")
async def report_client_error(req: Request, report: ClientErrorReport):
    """
    Receive a Flutter crash/error report and notify developers.
    Returns 200 in all cases — this handler must never surface errors to clients.
    """
    try:
        # IP-based rate limiting
        client_ip = req.client.host if req.client else "unknown"
        rate_key = f"error_report_rate:{client_ip}"
        count = await CacheService.increment_counter(rate_key, ttl=_RATE_WINDOW)
        if count > _RATE_LIMIT:
            logger.warning(
                "Error report rate limit exceeded for IP %s (count=%d)", client_ip, count
            )
            return {"status": "ok", "note": "rate_limited"}

        # Log to server logs
        logger.error(
            "CLIENT_ERROR source=%s type=%s context=%s platform=%s user_id=%s message=%s",
            report.source,
            report.error_type or "Unknown",
            report.context or "unknown",
            report.platform or "unknown",
            report.user_id or "anonymous",
            report.message[:200],
        )

        # Build extra context dict for email
        extra: dict = {"client_ip": client_ip}
        if report.platform:    extra["platform"]         = report.platform
        if report.app_version: extra["app_version"]      = report.app_version
        if report.user_id:     extra["user_id"]          = str(report.user_id)
        if report.screen:      extra["screen"]           = report.screen
        if report.context:     extra["error_context"]    = report.context
        if report.timestamp:   extra["client_timestamp"] = report.timestamp

        platform_label = (report.platform or "Flutter").title()
        await send_alert_email(
            subject=f"Client Error [{platform_label}] — {report.error_type or 'Exception'}",
            source=report.source,
            error_type=report.error_type or "UnknownError",
            message=report.message,
            tb=report.stack_trace or "",
            extra=extra,
        )
        await log_error_to_db(
            source=report.source or "flutter",
            severity="error",
            error_type=report.error_type or "UnknownError",
            message=report.message,
            stack_trace=report.stack_trace or "",
            client_ip=client_ip,
            user_id=report.user_id,
            platform=report.platform or "",
            app_version=report.app_version or "",
            screen=report.screen or "",
            context=report.context or "",
        )

    except Exception as exc:
        logger.warning("Error in error report handler (non-critical): %s", exc)

    return {"status": "ok"}
