"""Sprint 1: frequency-aware due filtering in fn_get_due_reminders

Revision ID: 015
Revises: 014
Create Date: 2026-09-04
"""
from alembic import op

revision = "015"
down_revision = "014_medicine_enrichment"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Weekly/monthly/fortnightly use start_date as calendar anchor.
    # Daily / multi-daily / as_needed remain time-of-day only.
    # Missing start_date keeps legacy time-only behaviour for those rows.
    op.execute("""
CREATE OR REPLACE FUNCTION public.fn_get_due_reminders(p_window_minutes integer DEFAULT 5)
 RETURNS TABLE(
    schedule_id         integer,
    user_id             integer,
    fcm_token           character varying,
    family_member_name  character varying,
    medicine_name       character varying,
    dosage              character varying,
    instructions        text,
    due_time            text
 )
 LANGUAGE plpgsql
 STABLE
AS $$
DECLARE
    _now_sydney TIMESTAMP;
    _now_time   TEXT;
    _today      DATE;
BEGIN
    _now_sydney := NOW() AT TIME ZONE 'Australia/Sydney';
    _now_time   := TO_CHAR(_now_sydney, 'HH24:MI');
    _today      := (_now_sydney)::DATE;

    RETURN QUERY
    SELECT
        ms.id,
        ms.user_id,
        u.fcm_token,
        fm.name,
        ms.medicine_name,
        ms.dosage,
        ms.instructions,
        t.reminder_time
    FROM medication_schedules ms
    JOIN  users u  ON u.id  = ms.user_id AND u.is_active = TRUE
    LEFT JOIN family_members fm ON fm.id = ms.family_member_id
    CROSS JOIN LATERAL jsonb_array_elements_text(ms.times::jsonb) AS t(reminder_time)
    WHERE ms.is_active = TRUE
      AND ms.times IS NOT NULL
      AND ms.times <> ''
      AND u.fcm_token IS NOT NULL
      AND (ms.start_date IS NULL OR ms.start_date <= _today)
      AND (ms.end_date   IS NULL OR ms.end_date   >= _today)
      AND ABS(
            EXTRACT(EPOCH FROM (
                TO_TIMESTAMP(t.reminder_time, 'HH24:MI')::TIME::INTERVAL
              - TO_TIMESTAMP(_now_time,       'HH24:MI')::TIME::INTERVAL
            ))
          ) <= p_window_minutes * 60
      AND (
            -- Daily-family frequencies (and unknown/empty): every day
            COALESCE(LOWER(ms.frequency), '') IN (
                '', 'daily', 'twice_daily', 'three_times_daily',
                'four_times_daily', 'as_needed'
            )
            OR (
                LOWER(ms.frequency) = 'weekly'
                AND (
                    ms.start_date IS NULL
                    OR EXTRACT(ISODOW FROM ms.start_date) = EXTRACT(ISODOW FROM _today)
                )
            )
            OR (
                LOWER(ms.frequency) = 'fortnightly'
                AND (
                    ms.start_date IS NULL
                    OR MOD((_today - ms.start_date), 14) = 0
                )
            )
            OR (
                LOWER(ms.frequency) = 'monthly'
                AND (
                    ms.start_date IS NULL
                    OR EXTRACT(DAY FROM ms.start_date) = EXTRACT(DAY FROM _today)
                    OR (
                        EXTRACT(DAY FROM ms.start_date) > EXTRACT(
                            DAY FROM (DATE_TRUNC('month', _today) + INTERVAL '1 month - 1 day')
                        )
                        AND EXTRACT(DAY FROM _today) = EXTRACT(
                            DAY FROM (DATE_TRUNC('month', _today) + INTERVAL '1 month - 1 day')
                        )
                    )
                )
            )
          );
END;
$$;
""")


def downgrade() -> None:
    # Restore Sprint-0 / migration 007 body (time-of-day only).
    op.execute("""
CREATE OR REPLACE FUNCTION public.fn_get_due_reminders(p_window_minutes integer DEFAULT 5)
 RETURNS TABLE(
    schedule_id         integer,
    user_id             integer,
    fcm_token           character varying,
    family_member_name  character varying,
    medicine_name       character varying,
    dosage              character varying,
    instructions        text,
    due_time            text
 )
 LANGUAGE plpgsql
 STABLE
AS $$
DECLARE
    _now_time TEXT;
BEGIN
    _now_time := TO_CHAR(NOW() AT TIME ZONE 'Australia/Sydney', 'HH24:MI');

    RETURN QUERY
    SELECT
        ms.id,
        ms.user_id,
        u.fcm_token,
        fm.name,
        ms.medicine_name,
        ms.dosage,
        ms.instructions,
        t.reminder_time
    FROM medication_schedules ms
    JOIN  users u  ON u.id  = ms.user_id AND u.is_active = TRUE
    LEFT JOIN family_members fm ON fm.id = ms.family_member_id
    CROSS JOIN LATERAL jsonb_array_elements_text(ms.times::jsonb) AS t(reminder_time)
    WHERE ms.is_active = TRUE
      AND ms.times IS NOT NULL
      AND ms.times <> ''
      AND u.fcm_token IS NOT NULL
      AND (ms.start_date IS NULL OR ms.start_date <= CURRENT_DATE)
      AND (ms.end_date   IS NULL OR ms.end_date   >= CURRENT_DATE)
      AND ABS(
            EXTRACT(EPOCH FROM (
                TO_TIMESTAMP(t.reminder_time, 'HH24:MI')::TIME::INTERVAL
              - TO_TIMESTAMP(_now_time,       'HH24:MI')::TIME::INTERVAL
            ))
          ) <= p_window_minutes * 60;
END;
$$;
""")
