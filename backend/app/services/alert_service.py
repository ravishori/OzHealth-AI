"""
Alert service for HealthNest.

Provides two reusable operations:
  1. send_alert_email()  â€” HTML email to all developer recipients
  2. log_error_to_db()   â€” Persist to the error_logs table

Both operations are non-blocking and never raise â€” failures are logged
at WARNING level and silently discarded so that error handling code can
never cause a secondary crash.

Extracted from main.py so that any service or route can import and call
these helpers without creating circular imports.
"""
import asyncio
import logging
import os
import smtplib
import socket
from datetime import datetime, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.core.config import settings
from app.core.request_context import get_correlation_id

logger = logging.getLogger(__name__)

# â”€â”€ Environment / Machine constants (set once at import time) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
_ENVIRONMENT: str = os.getenv("ENV", "development")
_HOSTNAME:    str = socket.gethostname()

# â”€â”€ HTML email template â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

_ALERT_HTML_TEMPLATE = """\
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:Arial,sans-serif;background:#f4f4f4;margin:0;padding:20px;">
  <div style="max-width:700px;margin:0 auto;background:#fff;border-radius:8px;overflow:hidden;
              box-shadow:0 2px 8px rgba(0,0,0,.12);">
    <!-- Header -->
    <div style="background:{header_color};padding:20px 24px;">
      <h2 style="margin:0;color:#fff;font-size:18px;">{emoji} {app_name} â€” {subject}</h2>
    </div>
    <!-- Body -->
    <div style="padding:24px;">
      <table style="width:100%;border-collapse:collapse;font-size:14px;">
        {meta_rows}
      </table>
      {traceback_block}
    </div>
    <!-- Footer -->
    <div style="background:#f9f9f9;padding:12px 24px;font-size:11px;color:#999;border-top:1px solid #eee;">
      Sent by {app_name} error monitor &bull; {timestamp} UTC &bull;
      Environment: {environment} &bull; Host: {hostname}
    </div>
  </div>
</body>
</html>"""


def _meta_row(label: str, value: str) -> str:
    return (
        f'<tr>'
        f'<td style="padding:6px 12px 6px 0;color:#666;white-space:nowrap;vertical-align:top;'
        f'font-weight:600;width:160px;">{label}</td>'
        f'<td style="padding:6px 0;color:#222;word-break:break-all;">{value}</td>'
        f'</tr>'
    )


def _build_html(
    subject: str,
    source: str,
    error_type: str,
    message: str,
    tb: str,
    extra: dict | None,
    correlation_id: str,
) -> str:
    is_backend = source in ("backend", "server")
    emoji = "ðŸ”´" if is_backend else "ðŸ“±"
    header_color = "#c0392b" if is_backend else "#2980b9"

    rows = ""
    rows += _meta_row("Source", source.upper())
    rows += _meta_row("Error Type", error_type)
    rows += _meta_row("Message", message)
    if correlation_id:
        rows += _meta_row("Correlation ID", correlation_id)
    if extra:
        for k, v in extra.items():
            rows += _meta_row(k.replace("_", " ").title(), str(v))

    tb_block = ""
    if tb:
        escaped = tb.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        tb_block = (
            '<h3 style="margin:20px 0 8px;font-size:14px;color:#333;">Stack Trace</h3>'
            '<pre style="background:#1e1e1e;color:#d4d4d4;padding:16px;border-radius:6px;'
            'font-size:12px;overflow-x:auto;white-space:pre-wrap;word-break:break-all;">'
            f'{escaped}</pre>'
        )

    return _ALERT_HTML_TEMPLATE.format(
        header_color=header_color,
        emoji=emoji,
        app_name=settings.APP_NAME,
        subject=subject,
        meta_rows=rows,
        traceback_block=tb_block,
        timestamp=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        environment=_ENVIRONMENT,
        hostname=_HOSTNAME,
    )


# â”€â”€ Synchronous SMTP send (runs in thread pool) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

def _send_email_sync(
    subject: str,
    source: str,
    error_type: str,
    message: str,
    tb: str,
    extra: dict | None,
    correlation_id: str,
) -> None:
    try:
        if not settings.SMTP_EMAIL or not settings.SMTP_PASSWORD:
            logger.warning("Alert email skipped â€” SMTP not configured")
            return

        recipients = settings.get_developer_emails()
        if not recipients:
            logger.warning("Alert email skipped â€” DEVELOPER_EMAILS not set")
            return

        html_body = _build_html(subject, source, error_type, message, tb, extra, correlation_id)

        plain = (
            f"[{settings.APP_NAME}] {subject}\n\n"
            f"Source: {source}\nError type: {error_type}\nMessage: {message}\n"
        )
        if correlation_id:
            plain += f"Correlation ID: {correlation_id}\n"
        if extra:
            for k, v in extra.items():
                plain += f"{k}: {v}\n"
        if tb:
            plain += f"\nStack Trace:\n{tb}\n"
        plain += (
            f"\nTimestamp: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC\n"
            f"Environment: {_ENVIRONMENT} | Host: {_HOSTNAME}\n"
        )

        msg = MIMEMultipart("alternative")
        msg["Subject"] = f"[{settings.APP_NAME}] {subject}"
        msg["From"]    = settings.SMTP_EMAIL
        msg["To"]      = ", ".join(recipients)
        msg.attach(MIMEText(plain, "plain"))
        msg.attach(MIMEText(html_body, "html"))

        with smtplib.SMTP(settings.SMTP_SERVER, settings.SMTP_PORT, timeout=10) as srv:
            srv.ehlo()
            srv.starttls()
            srv.ehlo()
            srv.login(settings.SMTP_EMAIL, settings.SMTP_PASSWORD)
            srv.sendmail(settings.SMTP_EMAIL, recipients, msg.as_string())

        logger.info(
            "Alert email sent to %d recipient(s): %s", len(recipients), subject
        )
    except Exception as exc:
        logger.warning("Alert email failed (non-critical): %s", exc)


# â”€â”€ Public API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async def send_alert_email(
    subject: str,
    source: str = "backend",
    error_type: str = "Exception",
    message: str = "",
    tb: str = "",
    extra: dict | None = None,
    correlation_id: str = "",
) -> None:
    """
    Non-blocking alert email â€” fires in thread pool so SMTP never stalls the
    async event loop.  Fire-and-forget: never raises.

    If correlation_id is not provided, it is read automatically from the
    current request context.
    """
    try:
        cid = correlation_id or get_correlation_id()
        asyncio.create_task(
            asyncio.to_thread(
                _send_email_sync, subject, source, error_type, message, tb, extra, cid
            )
        )
    except Exception as exc:
        logger.warning("Could not schedule alert email: %s", exc)


async def log_error_to_db(
    source: str = "backend",
    error_type: str = "",
    message: str = "",
    stack_trace: str = "",
    request_path: str = "",
    http_method: str = "",
    client_ip: str = "",
    user_id: int | None = None,
    platform: str = "",
    app_version: str = "",
    screen: str = "",
    context: str = "",
    severity: str = "error",
    correlation_id: str = "",
) -> None:
    """
    Persist an error record to the error_logs table.  Never raises.

    If correlation_id is not provided, it is read automatically from the
    current request context.
    """
    try:
        from app.core.database import AsyncSessionLocal
        from app.models.error_log import ErrorLog

        cid = correlation_id or get_correlation_id()

        async with AsyncSessionLocal() as db:
            entry = ErrorLog(
                source=source[:50],
                error_type=(error_type or "")[:200] or None,
                message=(message or "")[:5000],
                stack_trace=(stack_trace or "")[:10000] or None,
                request_path=(request_path or "")[:500] or None,
                http_method=(http_method or "")[:10] or None,
                client_ip=(client_ip or "")[:50] or None,
                user_id=user_id,
                platform=(platform or "")[:50] or None,
                app_version=(app_version or "")[:50] or None,
                screen=(screen or "")[:200] or None,
                context=(context or "")[:200] or None,
                severity=(severity or "error")[:20],
                correlation_id=(cid or "")[:64] or None,
                environment=_ENVIRONMENT[:50],
                hostname=_HOSTNAME[:200],
            )
            db.add(entry)
            await db.commit()
    except Exception as exc:
        logger.warning("Failed to persist error to DB (non-critical): %s", exc)
