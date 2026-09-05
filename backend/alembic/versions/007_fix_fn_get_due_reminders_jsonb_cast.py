"""fix fn_get_due_reminders jsonb cast for TEXT column

Revision ID: 007
Revises: 006
Create Date: 2026-03-28
"""
from alembic import op

revision = '007'
down_revision = '006'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Recreate fn_get_due_reminders with explicit ::jsonb cast on the TEXT column.
    # After migration 004/005 the 'times' column is stored as TEXT (containing JSON),
    # so jsonb_array_elements_text() fails without the explicit cast.
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
    -- Cast TEXT -> jsonb before unnesting
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


def downgrade() -> None:
    # Restore the original (broken) version — only useful for rollback testing
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
    CROSS JOIN LATERAL jsonb_array_elements_text(ms.times) AS t(reminder_time)
    WHERE ms.is_active = TRUE
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
