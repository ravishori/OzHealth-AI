"""Unit tests for medication frequency normalization and due-day logic."""
from datetime import date

import pytest

from app.schemas.medication import normalize_medication_frequency
from app.services.reminder_due import is_due_on_date


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("Daily", "daily"),
        ("daily", "daily"),
        ("DAILY", "daily"),
        ("Twice Daily", "twice_daily"),
        ("twice_daily", "twice_daily"),
        ("Three Times Daily", "three_times_daily"),
        ("Weekly", "weekly"),
        ("Monthly", "monthly"),
        ("As Needed", "as_needed"),
        ("as-needed", "as_needed"),
        ("Four Times Daily", "four_times_daily"),
        ("fortnightly", "fortnightly"),
    ],
)
def test_normalize_frequency_aliases(raw, expected):
    assert normalize_medication_frequency(raw) == expected


def test_normalize_frequency_rejects_unknown():
    with pytest.raises(ValueError):
        normalize_medication_frequency("every other Tuesday")


def test_daily_always_due():
    assert is_due_on_date("daily", date(2026, 9, 4), start_date=date(2026, 9, 1))


def test_weekly_matches_weekday_of_start():
    # 2026-09-04 is Friday
    start = date(2026, 9, 4)
    assert is_due_on_date("weekly", date(2026, 9, 11), start_date=start)  # next Fri
    assert not is_due_on_date("weekly", date(2026, 9, 5), start_date=start)  # Sat


def test_monthly_matches_day_of_month():
    start = date(2026, 1, 15)
    assert is_due_on_date("monthly", date(2026, 2, 15), start_date=start)
    assert not is_due_on_date("monthly", date(2026, 2, 14), start_date=start)


def test_monthly_clamps_short_month():
    start = date(2026, 1, 31)
    assert is_due_on_date("monthly", date(2026, 2, 28), start_date=start)


def test_fortnightly():
    start = date(2026, 9, 1)
    assert is_due_on_date("fortnightly", date(2026, 9, 15), start_date=start)
    assert not is_due_on_date("fortnightly", date(2026, 9, 8), start_date=start)


def test_before_start_not_due():
    assert not is_due_on_date("daily", date(2026, 9, 1), start_date=date(2026, 9, 4))


def test_legacy_weekly_without_start_still_due():
    assert is_due_on_date("weekly", date(2026, 9, 4), start_date=None)
