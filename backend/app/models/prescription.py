from sqlalchemy import Column, Integer, String, ForeignKey, Text, DateTime
from sqlalchemy.sql import func
from app.core.database import Base
from app.services.encryption_service import EncryptedText


class Prescription(Base):
    __tablename__ = "prescriptions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    medical_record_id = Column(Integer, ForeignKey("medical_records.id", ondelete="SET NULL"), nullable=True)
    family_member_id = Column(Integer, ForeignKey("family_members.id", ondelete="SET NULL"), nullable=True)
    doctor_name = Column(String(255), nullable=True)
    hospital = Column(String(500), nullable=True)
    prescription_date = Column(DateTime(timezone=True), nullable=True)
    raw_ocr_text = Column(EncryptedText, nullable=True)          # encrypted OCR output
    extracted_medicines = Column(EncryptedText, nullable=True)   # encrypted JSON array
    ai_summary = Column(EncryptedText, nullable=True)            # encrypted AI analysis
    created_at = Column(DateTime(timezone=True), server_default=func.now())
