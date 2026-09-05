"""
Function-level execution tracing for HealthNest.

Two mechanisms:

1. LoggedAPIRoute
   A custom FastAPI route class.  Wrap any APIRouter with it and every
   endpoint in that router is automatically traced:

       router = APIRouter(route_class=LoggedAPIRoute)

   Each request logs:
       ENTER  <handler_name>  <METHOD> <path>
       OK     <handler_name>  (<duration> ms)   â† 2xx
       WARN   <handler_name>  HTTP <4xx>         â† expected client error
       FAIL   <handler_name>  (<duration> ms)    â† 5xx / unhandled exception

2. @log_fn decorator
   Apply to any async or sync helper function to get the same ENTER / OK /
   FAIL tracing with duration.

       @log_fn
       async def my_service_function(...):
           ...

All traces go to the "vitapulse.functions" logger â†’ logs/functions.log
(daily rotation, 7-day retention â€” configured in logging_config.py).
"""
import asyncio
import functools
import logging
import time
from typing import Callable, Any

from fastapi import Request, Response, HTTPException
from fastapi.routing import APIRoute

# â”€â”€ Logger (goes to functions.log via logging_config.setup_logging) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
fn_log = logging.getLogger("vitapulse.functions")


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# 1.  FastAPI custom route class
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class LoggedAPIRoute(APIRoute):
    """
    Drop-in replacement for the default FastAPI APIRoute.

    Usage:
        router = APIRouter(route_class=LoggedAPIRoute)

    Wraps every endpoint's handler to emit structured log lines to
    functions.log with timing and success/failure status.
    """

    def get_route_handler(self) -> Callable:
        original = super().get_route_handler()
        route_name = self.name or "unknown"

        async def traced_handler(request: Request) -> Response:
            start = time.perf_counter()
            fn_log.debug(
                "ENTER %s",
                route_name,
                extra={
                    "fn": route_name,
                    "method": request.method,
                    "path": str(request.url.path),
                    "status": "enter",
                },
            )
            try:
                response: Response = await original(request)
                duration_ms = round((time.perf_counter() - start) * 1000, 1)
                fn_log.info(
                    "OK %s (%.1f ms)",
                    route_name,
                    duration_ms,
                    extra={
                        "fn": route_name,
                        "status": "ok",
                        "duration_ms": duration_ms,
                    },
                )
                return response

            except HTTPException as exc:
                duration_ms = round((time.perf_counter() - start) * 1000, 1)
                # 4xx are expected client errors â€” warn, not error
                level = logging.WARNING if exc.status_code < 500 else logging.ERROR
                fn_log.log(
                    level,
                    "HTTP%d %s (%.1f ms) â€” %s",
                    exc.status_code,
                    route_name,
                    duration_ms,
                    exc.detail,
                    extra={
                        "fn": route_name,
                        "status": "http_error",
                        "status_code": exc.status_code,
                        "duration_ms": duration_ms,
                        "detail": str(exc.detail),
                    },
                )
                raise

            except Exception as exc:
                duration_ms = round((time.perf_counter() - start) * 1000, 1)
                fn_log.error(
                    "FAIL %s (%.1f ms) â€” %s: %s",
                    route_name,
                    duration_ms,
                    type(exc).__name__,
                    exc,
                    extra={
                        "fn": route_name,
                        "status": "fail",
                        "duration_ms": duration_ms,
                        "error_type": type(exc).__name__,
                        "error": str(exc),
                    },
                    exc_info=True,
                )
                raise

        return traced_handler


# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# 2.  General-purpose @log_fn decorator
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

def log_fn(func: Callable) -> Callable:
    """
    Decorator that traces any async or sync function.

    Logs ENTER at DEBUG, OK at INFO, FAIL at ERROR.
    Safe to stack with other decorators.

    Example:
        @log_fn
        async def _sp_insert_otp(db, ...):
            ...
    """
    qualified_name = f"{func.__module__}.{func.__qualname__}"

    if asyncio.iscoroutinefunction(func):
        @functools.wraps(func)
        async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
            start = time.perf_counter()
            fn_log.debug(
                "ENTER %s",
                qualified_name,
                extra={"fn": qualified_name, "status": "enter"},
            )
            try:
                result = await func(*args, **kwargs)
                duration_ms = round((time.perf_counter() - start) * 1000, 1)
                fn_log.info(
                    "OK %s (%.1f ms)",
                    qualified_name,
                    duration_ms,
                    extra={"fn": qualified_name, "status": "ok", "duration_ms": duration_ms},
                )
                return result
            except Exception as exc:
                duration_ms = round((time.perf_counter() - start) * 1000, 1)
                fn_log.error(
                    "FAIL %s (%.1f ms) â€” %s: %s",
                    qualified_name,
                    duration_ms,
                    type(exc).__name__,
                    exc,
                    extra={
                        "fn": qualified_name,
                        "status": "fail",
                        "duration_ms": duration_ms,
                        "error_type": type(exc).__name__,
                        "error": str(exc),
                    },
                    exc_info=True,
                )
                raise
        return async_wrapper

    else:
        @functools.wraps(func)
        def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
            start = time.perf_counter()
            fn_log.debug(
                "ENTER %s",
                qualified_name,
                extra={"fn": qualified_name, "status": "enter"},
            )
            try:
                result = func(*args, **kwargs)
                duration_ms = round((time.perf_counter() - start) * 1000, 1)
                fn_log.info(
                    "OK %s (%.1f ms)",
                    qualified_name,
                    duration_ms,
                    extra={"fn": qualified_name, "status": "ok", "duration_ms": duration_ms},
                )
                return result
            except Exception as exc:
                duration_ms = round((time.perf_counter() - start) * 1000, 1)
                fn_log.error(
                    "FAIL %s (%.1f ms) â€” %s: %s",
                    qualified_name,
                    duration_ms,
                    type(exc).__name__,
                    exc,
                    extra={
                        "fn": qualified_name,
                        "status": "fail",
                        "duration_ms": duration_ms,
                        "error_type": type(exc).__name__,
                        "error": str(exc),
                    },
                    exc_info=True,
                )
                raise
        return sync_wrapper
