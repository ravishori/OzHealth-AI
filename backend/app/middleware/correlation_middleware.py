"""
Correlation ID middleware for HealthNest.

For every incoming HTTP request:
  1. Read X-Request-ID, X-Correlation-ID, or X-Trace-ID from the request
     headers (in that order).  If none are present, generate a fresh UUID4
     hex string.
  2. Store the ID in an async-safe ContextVar (request_context.py) so it is
     accessible to all code paths in this request â€” route handlers, service
     calls, background tasks spawned in-request, and the JsonFormatter.
  3. Echo the ID back in the X-Request-ID response header so API callers
     (Flutter app, API gateways) can correlate their client logs with server
     logs using a single ID.

Every JSON log line emitted during the request automatically includes
"correlation_id" via the JsonFormatter in logging_config.py.
"""
import uuid
import logging
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.request_context import set_correlation_id

logger = logging.getLogger(__name__)

_CANDIDATE_HEADERS = ("X-Request-ID", "X-Correlation-ID", "X-Trace-ID")
_RESPONSE_HEADER   = "X-Request-ID"


class CorrelationIdMiddleware(BaseHTTPMiddleware):
    """
    Attaches a Correlation / Request ID to every HTTP request.

    ID precedence (first header found wins):
      1. X-Request-ID
      2. X-Correlation-ID
      3. X-Trace-ID
      4. Generated UUID4 hex string

    The resolved ID is echoed back in the X-Request-ID response header.
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        cid: str | None = None
        for header in _CANDIDATE_HEADERS:
            cid = request.headers.get(header)
            if cid:
                break
        if not cid:
            cid = uuid.uuid4().hex

        set_correlation_id(cid)

        response = await call_next(request)
        response.headers[_RESPONSE_HEADER] = cid
        return response
