from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Boolean
from sqlalchemy.sql import func
from app.core.database import Base
from app.services.encryption_service import EncryptedText


class FamilyMember(Base):
    __tablename__ = "family_members"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    relationship = Column(String(100), nullable=True)
    age = Column(Integer, nullable=True)
    gender = Column(String(20), nullable=True)
    blood_group = Column(String(10), nullable=True)
    # Clinical PHI — same EncryptedText TypeDecorator as users.health_conditions
    # / users.allergies / medical_records.notes. Columns are already TEXT
    # (alembic 005); no DDL. Identity fields stay plaintext like User.
    medical_conditions = Column(EncryptedText, nullable=True)
    allergies = Column(EncryptedText, nullable=True)
    notes = Column(EncryptedText, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
