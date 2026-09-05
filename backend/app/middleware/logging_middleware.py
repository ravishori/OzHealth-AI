"""
Request/response logging middleware for HealthNest.

Logs per request: method, path, status_code, duration_ms, user_id
(from JWT when present), and correlation_id (from CorrelationIdMiddleware).

Slow request detection:
  >2 000 ms  â†’ WARNING in app.log and performance.log
  >5 000 ms  â†’ ERROR   in app.log and performance.log

PII in URL paths is NOT logged â€” only structural information.
"""
import time
import logging
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from app.core.security import decode_token
from app.core.request_context import get_correlation_id
from app.core.logging_config import perf_log

logger = logging.getLogger("vitapulse.http")

# Paths to skip (health probes, static files)
_SKIP_PATHS = {"/", "/health", "/docs", "/openapi.json", "/redoc"}

# Slow request thresholds (milliseconds)
_SLOW_WARN_MS  = 2_000
_SLOW_ERROR_MS = 5_000


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        if request.url.path in _SKIP_PATHS or request.url.path.startswith("/uploads"):
            return await call_next(request)

        start = time.perf_counter()

        # Extract user_id from JWT (best-effort, never fail)
        user_id = None
        try:
            auth = request.headers.get("Authorization", "")
            if auth.startswith("Bearer "):
                payload = decode_token(auth[7:])
                user_id = payload.get("sub")
        except Exception:
            pass

        response = await call_next(request)
        duration_ms = round((time.perf_counter() - start) * 1000, 1)
        cid = get_correlation_id()

        log_extra = {
            "method":         request.method,
            "path":           request.url.path,
            "status_code":    response.status_code,
            "duration_ms":    duration_ms,
            "user_id":        user_id,
            "correlation_id": cid,
        }

        # Normal request log
        level = logging.WARNING if response.status_code >= 400 else logging.INFO
        logger.log(
            level,
            "HTTP %s %s â†’ %s (%.1f ms)",
            request.method,
            request.url.path,
            response.status_code,
            duration_ms,
            extra=log_extra,
        )

        # Slow request detection â€” write to performance.log
        if duration_ms >= _SLOW_ERROR_MS:
            perf_log.error(
                "CRITICAL_SLOW_REQUEST %.1f ms â€” %s %s â†’ %s (cid=%s)",
                duration_ms,
                request.method,
                request.url.path,
                response.status_code,
                cid,
                extra={**log_extra, "threshold_ms": _SLOW_ERROR_MS, "alert": True},
            )
        elif duration_ms >= _SLOW_WARN_MS:
            perf_log.warning(
                "SLOW_REQUEST %.1f ms â€” %s %s â†’ %s (cid=%s)",
                duration_ms,
                request.method,
                request.url.path,
                response.status_code,
                cid,
                extra={**log_extra, "threshold_ms": _SLOW_WARN_MS},
            )

        return response
