"""
Push notification service for VitaPulse AI.

Supports:
  - FCM (Firebase Cloud Messaging) via firebase-admin SDK
  - Fallback: logs to console when FCM is not configured

Usage:
    from app.services.notification_service import NotificationService
    await NotificationService.send(token, title, body, data)
    await NotificationService.send_medication_reminder(schedule)
"""

import logging
from typing import Optional
from datetime import datetime, date

logger = logging.getLogger(__name__)

# ─── Lazy FCM initialisation ─────────────────────────────────────────────────

_fcm_app = None
_fcm_available = False


def _init_fcm() -> bool:
    """Attempt to initialise Firebase Admin SDK once."""
    global _fcm_app, _fcm_available
    if _fcm_app is not None:
        return _fcm_available
    try:
        import firebase_admin
        from firebase_admin import credentials
        import os

        cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
        if not cred_path:
            logger.info(
                "FIREBASE_CREDENTIALS_PATH not set — push notifications disabled."
            )
            _fcm_available = False
            return False

        cred = credentials.Certificate(cred_path)
        _fcm_app = firebase_admin.initialize_app(cred)
        _fcm_available = True
        logger.info("Firebase Admin SDK initialised.")
        return True
    except Exception as exc:
        logger.warning("Firebase Admin SDK init failed: %s", exc)
        _fcm_available = False
        return False


# ─── Core send helper ────────────────────────────────────────────────────────

async def _send_fcm(
    token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Send a single FCM notification. Returns True on success."""
    if not _init_fcm():
        logger.info(
            "[PUSH NOTIFICATION - dev mode]\n  token: %s...\n  title: %s\n  body: %s",
            token[:20],
            title,
            body,
        )
        return True  # treat as success in dev mode

    try:
        from firebase_admin import messaging

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=token,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    icon="ic_notification",
                    color="#00897B",
                    channel_id="vitapulse_reminders",
                ),
            ),
        )
        response = messaging.send(message)
        logger.debug("FCM response: %s", response)
        return True
    except Exception as exc:
        logger.error("FCM send failed for token %s...: %s", token[:20], exc)
        return False


# ─── Public API ──────────────────────────────────────────────────────────────

class NotificationService:

    @staticmethod
    async def send(
        fcm_token: str,
        title: str,
        body: str,
        data: Optional[dict] = None,
    ) -> bool:
        """Generic push notification."""
        return await _send_fcm(fcm_token, title, body, data)

    @staticmethod
    async def send_medication_reminder(schedule: dict) -> bool:
        """
        Send a medication reminder notification.

        schedule dict keys (from the v_active_reminders_today view):
            user_id, fcm_token, medicine_name, dosage,
            family_member_name (optional), instructions
        """
        medicine = schedule.get("medicine_name", "your medication")
        dosage = schedule.get("dosage", "")
        family_member = schedule.get("family_member_name")

        if family_member:
            title = f"Medication Reminder — {family_member}"
            body = f"Time for {medicine}" + (f" {dosage}" if dosage else "")
        else:
            title = "Medication Reminder"
            body = f"Time to take {medicine}" + (f" {dosage}" if dosage else "")

        instructions = schedule.get("instructions")
        if instructions:
            body += f"\n{instructions}"

        return await _send_fcm(
            schedule["fcm_token"],
            title,
            body,
            data={
                "type": "medication_reminder",
                "schedule_id": str(schedule.get("schedule_id", "")),
                "medicine_name": medicine,
            },
        )

    @staticmethod
    async def send_refill_alert(schedule: dict) -> bool:
        """
        Notify the user that a medication is running low or refill is due.

        schedule dict keys: fcm_token, medicine_name, remaining_quantity,
                            refill_date, alert_type
        """
        medicine = schedule.get("medicine_name", "your medication")
        alert_type = schedule.get("alert_type", "refill_due")
        remaining = schedule.get("remaining_quantity")
        refill_date = schedule.get("refill_date")

        if alert_type == "low_stock" and remaining is not None:
            title = "Low Stock Alert"
            body = f"Only {remaining} tablet(s) of {medicine} remaining. Time to refill!"
        else:
            days = schedule.get("days_until_refill")
            title = "Refill Reminder"
            if days is not None and days <= 0:
                body = f"Refill for {medicine} is due today."
            elif days is not None:
                body = f"Refill for {medicine} due in {days} day(s)."
            else:
                body = f"Time to refill {medicine}."

        return await _send_fcm(
            schedule["fcm_token"],
            title,
            body,
            data={
                "type": "refill_alert",
                "medicine_name": medicine,
                "alert_type": alert_type,
            },
        )

    @staticmethod
    async def send_sos_alert(
        fcm_token: str,
        user_name: str,
        location_url: Optional[str] = None,
        message: Optional[str] = None,
    ) -> bool:
        """Notify an emergency contact that SOS was triggered."""
        body = f"{user_name} has triggered an SOS emergency alert."
        if message:
            body += f" Message: {message}"
        if location_url:
            body += f"\nLocation: {location_url}"

        return await _send_fcm(
            fcm_token,
            title="🚨 Emergency SOS Alert",
            body=body,
            data={
                "type": "sos",
                "user_name": user_name,
                "location_url": location_url or "",
            },
        )

    @staticmethod
    async def send_health_reminder(
        fcm_token: str,
        metric_type: str,
    ) -> bool:
        """Remind user to log a health metric."""
        labels = {
            "blood_pressure_systolic": "blood pressure",
            "blood_sugar": "blood sugar",
            "heart_rate": "heart rate",
            "weight": "weight",
            "oxygen_level": "oxygen level",
            "temperature": "temperature",
        }
        label = labels.get(metric_type, metric_type.replace("_", " "))
        return await _send_fcm(
            fcm_token,
            title="Health Monitoring Reminder",
            body=f"Don't forget to log your {label} today.",
            data={"type": "health_reminder", "metric_type": metric_type},
        )
