"""Reminder due-day semantics for medication schedules.

Canonical frequencies (DB CHECK + API normalize):
  daily, twice_daily, three_times_daily, four_times_daily,
  weekly, fortnightly, monthly, as_needed

Weekly / fortnightly / monthly use start_date as the calendar anchor:
  - weekly: same weekday as start_date (ISO Monday=1 … Sunday=7)
  - fortnightly: every 14 days from start_date
  - monthly: same day-of-month as start_date (clamped for short months)

If start_date is missing, weekly/monthly/fortnightly fall back to
time-of-day-only matching (legacy behaviour) so existing rows keep firing.
"""
from __future__ import annotations

from datetime import date, timedelta
from typing import Optional


def is_due_on_date(
    frequency: str,
    on_date: date,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
) -> bool:
    """Return True if a schedule with [frequency] should fire on [on_date]."""
    freq = (frequency or "").strip().lower()

    if start_date is not None and on_date < start_date:
        return False
    if end_date is not None and on_date > end_date:
        return False

    if freq in (
        "daily",
        "twice_daily",
        "three_times_daily",
        "four_times_daily",
        "as_needed",
        "",
    ):
        return True

    if start_date is None:
        # Legacy rows without start_date: keep prior time-only behaviour.
        return True

    if freq == "weekly":
        return on_date.isoweekday() == start_date.isoweekday()

    if freq == "fortnightly":
        delta = (on_date - start_date).days
        return delta >= 0 and delta % 14 == 0

    if freq == "monthly":
        # Same calendar day; if start was day 31 and month is shorter, use last day.
        target_day = start_date.day
        if on_date.day == target_day:
            return True
        # Last day of month when start_date.day exceeds this month's length
        next_month = date(on_date.year + (1 if on_date.month == 12 else 0),
                          1 if on_date.month == 12 else on_date.month + 1,
                          1)
        last_day = (next_month - timedelta(days=1)).day
        return target_day > last_day and on_date.day == last_day

    return True
