"""Initial migration — create all VitaPulse AI tables

Revision ID: 001
Revises:
Create Date: 2026-03-01 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

# revision identifiers, used by Alembic
revision = '001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ──────────────── users ────────────────
    op.create_table(
        'users',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('email', sa.String(255), nullable=True),
        sa.Column('phone', sa.String(20), nullable=True),
        sa.Column('age', sa.Integer(), nullable=True),
        sa.Column('gender', sa.String(20), nullable=True),
        sa.Column('blood_group', sa.String(10), nullable=True),
        sa.Column('health_conditions', JSONB(), server_default='[]'),
        sa.Column('allergies', JSONB(), server_default='[]'),
        sa.Column('lifestyle_preferences', JSONB(), server_default='{}'),
        sa.Column('profile_image_url', sa.Text(), nullable=True),
        sa.Column('fcm_token', sa.String(500), nullable=True),
        sa.Column('is_active', sa.Boolean(), server_default='true'),
        sa.Column('is_verified', sa.Boolean(), server_default='false'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('email'),
        sa.UniqueConstraint('phone'),
    )
    op.create_index('ix_users_email', 'users', ['email'])
    op.create_index('ix_users_phone', 'users', ['phone'])

    # ──────────────── otps ────────────────
    op.create_table(
        'otps',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('identifier', sa.String(255), nullable=False),
        sa.Column('otp_code', sa.String(10), nullable=False),
        sa.Column('purpose', sa.String(50), server_default='auth'),
        sa.Column('is_used', sa.Boolean(), server_default='false'),
        sa.Column('attempts', sa.Integer(), server_default='0'),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_otps_identifier', 'otps', ['identifier'])

    # ──────────────── family_members ────────────────
    op.create_table(
        'family_members',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('relationship', sa.String(100), nullable=True),
        sa.Column('age', sa.Integer(), nullable=True),
        sa.Column('gender', sa.String(20), nullable=True),
        sa.Column('blood_group', sa.String(10), nullable=True),
        sa.Column('medical_conditions', JSONB(), server_default='[]'),
        sa.Column('allergies', JSONB(), server_default='[]'),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('profile_image_url', sa.Text(), nullable=True),
        sa.Column('is_active', sa.Boolean(), server_default='true'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_family_user_id', 'family_members', ['user_id'])

    # ──────────────── medical_records ────────────────
    op.create_table(
        'medical_records',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('family_member_id', sa.Integer(), nullable=True),
        sa.Column('record_type', sa.String(50), nullable=False),
        sa.Column('title', sa.String(500), nullable=True),
        sa.Column('file_url', sa.Text(), nullable=True),
        sa.Column('file_name', sa.String(500), nullable=True),
        sa.Column('file_size', sa.Integer(), nullable=True),
        sa.Column('file_type', sa.String(20), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('record_date', sa.Date(), nullable=True),
        sa.Column('is_active', sa.Boolean(), server_default='true'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['family_member_id'], ['family_members.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_records_user_id', 'medical_records', ['user_id'])

    # ──────────────── prescriptions ────────────────
    op.create_table(
        'prescriptions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('family_member_id', sa.Integer(), nullable=True),
        sa.Column('medical_record_id', sa.Integer(), nullable=True),
        sa.Column('doctor_name', sa.String(255), nullable=True),
        sa.Column('hospital', sa.String(500), nullable=True),
        sa.Column('prescription_date', sa.Date(), nullable=True),
        sa.Column('raw_ocr_text', sa.Text(), nullable=True),
        sa.Column('extracted_medicines', sa.Text(), nullable=True),  # JSON string
        sa.Column('ai_summary', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['family_member_id'], ['family_members.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['medical_record_id'], ['medical_records.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_prescriptions_user_id', 'prescriptions', ['user_id'])

    # ──────────────── medicines ────────────────
    op.create_table(
        'medicines',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(500), nullable=False),
        sa.Column('generic_name', sa.String(500), nullable=True),
        sa.Column('brand_names', JSONB(), server_default='[]'),
        sa.Column('composition', sa.Text(), nullable=True),
        sa.Column('drug_class', sa.String(255), nullable=True),
        sa.Column('dosage_forms', JSONB(), server_default='[]'),
        sa.Column('standard_dosage', sa.Text(), nullable=True),
        sa.Column('side_effects', sa.Text(), nullable=True),
        sa.Column('interactions', sa.Text(), nullable=True),
        sa.Column('contraindications', sa.Text(), nullable=True),
        sa.Column('warnings', sa.Text(), nullable=True),
        sa.Column('storage_instructions', sa.Text(), nullable=True),
        sa.Column('pregnancy_category', sa.String(5), nullable=True),
        sa.Column('tga_registered', sa.Boolean(), server_default='false'),
        sa.Column('tga_artg_number', sa.String(50), nullable=True),
        sa.Column('schedule', sa.String(20), nullable=True),
        sa.Column('atc_code', sa.String(20), nullable=True),
        sa.Column('barcode', sa.String(100), nullable=True),
        sa.Column('search_vector', sa.Text(), nullable=True),  # TSVECTOR managed by trigger
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_medicines_name', 'medicines', ['name'])

    # ──────────────── medication_schedules ────────────────
    op.create_table(
        'medication_schedules',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('family_member_id', sa.Integer(), nullable=True),
        sa.Column('prescription_id', sa.Integer(), nullable=True),
        sa.Column('medicine_name', sa.String(500), nullable=False),
        sa.Column('dosage', sa.String(100), nullable=True),
        sa.Column('frequency', sa.String(50), nullable=False),
        sa.Column('times', JSONB(), server_default='[]'),
        sa.Column('instructions', sa.Text(), nullable=True),
        sa.Column('start_date', sa.Date(), nullable=True),
        sa.Column('end_date', sa.Date(), nullable=True),
        sa.Column('refill_date', sa.Date(), nullable=True),
        sa.Column('total_quantity', sa.Integer(), nullable=True),
        sa.Column('remaining_quantity', sa.Integer(), nullable=True),
        sa.Column('is_active', sa.Boolean(), server_default='true'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['family_member_id'], ['family_members.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['prescription_id'], ['prescriptions.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_schedules_user_id', 'medication_schedules', ['user_id'])

    # ──────────────── health_metrics ────────────────
    op.create_table(
        'health_metrics',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('family_member_id', sa.Integer(), nullable=True),
        sa.Column('metric_type', sa.String(50), nullable=False),
        sa.Column('value', sa.Numeric(10, 2), nullable=False),
        sa.Column('value2', sa.Numeric(10, 2), nullable=True),
        sa.Column('unit', sa.String(30), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('recorded_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['family_member_id'], ['family_members.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_metrics_user_id', 'health_metrics', ['user_id'])
    op.create_index('ix_metrics_trend', 'health_metrics', ['user_id', 'metric_type', 'recorded_at'])

    # ──────────────── emergency_contacts ────────────────
    op.create_table(
        'emergency_contacts',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('phone', sa.String(20), nullable=False),
        sa.Column('relationship', sa.String(100), nullable=True),
        sa.Column('is_primary', sa.Boolean(), server_default='false'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_emergency_user_id', 'emergency_contacts', ['user_id'])

    # ──────────────── ai_conversations ────────────────
    op.create_table(
        'ai_conversations',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('title', sa.String(500), nullable=True),
        sa.Column('context_type', sa.String(50), server_default='general'),
        sa.Column('messages', JSONB(), server_default='[]'),
        sa.Column('token_count', sa.Integer(), server_default='0'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_ai_conv_user_id', 'ai_conversations', ['user_id'])

    # ──────────────── audit_logs ────────────────
    op.create_table(
        'audit_logs',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('action', sa.String(100), nullable=False),
        sa.Column('resource_type', sa.String(100), nullable=True),
        sa.Column('resource_id', sa.Integer(), nullable=True),
        sa.Column('ip_address', sa.String(45), nullable=True),
        sa.Column('user_agent', sa.String(500), nullable=True),
        sa.Column('metadata', JSONB(), server_default='{}'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )

    # ──────────────── notification_logs ────────────────
    op.create_table(
        'notification_logs',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('medication_schedule_id', sa.Integer(), nullable=True),
        sa.Column('notification_type', sa.String(50), nullable=False),
        sa.Column('title', sa.String(255), nullable=True),
        sa.Column('body', sa.Text(), nullable=True),
        sa.Column('is_sent', sa.Boolean(), server_default='false'),
        sa.Column('sent_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('scheduled_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(
            ['medication_schedule_id'], ['medication_schedules.id'], ondelete='SET NULL'
        ),
        sa.PrimaryKeyConstraint('id'),
    )


def downgrade() -> None:
    op.drop_table('notification_logs')
    op.drop_table('audit_logs')
    op.drop_table('ai_conversations')
    op.drop_table('emergency_contacts')
    op.drop_table('health_metrics')
    op.drop_table('medication_schedules')
    op.drop_table('medicines')
    op.drop_table('prescriptions')
    op.drop_table('medical_records')
    op.drop_table('family_members')
    op.drop_table('otps')
    op.drop_table('users')
