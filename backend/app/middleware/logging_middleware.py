"""
Request/response logging middleware.
Logs: method, path, status_code, duration_ms, user_id (from JWT if present).
PII in paths is NOT logged — only structural info.
"""
import time
import logging
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from app.core.security import decode_token

logger = logging.getLogger("vitapulse.http")

# Paths to skip (health probes, static files)
_SKIP_PATHS = {"/", "/health", "/docs", "/openapi.json", "/redoc"}


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

        level = logging.WARNING if response.status_code >= 400 else logging.INFO
        logger.log(
            level,
            "HTTP %s %s → %s (%.1f ms)",
            request.method,
            request.url.path,
            response.status_code,
            duration_ms,
            extra={
                "method": request.method,
                "path": request.url.path,
                "status_code": response.status_code,
                "duration_ms": duration_ms,
                "user_id": user_id,
            },
        )

        return response
