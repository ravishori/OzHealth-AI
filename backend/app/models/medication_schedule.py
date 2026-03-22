from sqlalchemy import Column, Integer, String, ForeignKey, Text, DateTime, Boolean, Date
from sqlalchemy.sql import func
from app.core.database import Base


class MedicationSchedule(Base):
    __tablename__ = "medication_schedules"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    family_member_id = Column(Integer, ForeignKey("family_members.id", ondelete="SET NULL"), nullable=True)
    medicine_name = Column(String(500), nullable=False)
    dosage = Column(String(200), nullable=True)
    frequency = Column(String(100), nullable=False)  # daily, twice_daily, weekly, monthly
    times = Column(Text, nullable=True)  # JSON array of HH:MM strings
    instructions = Column(Text, nullable=True)  # take with food, etc.
    start_date = Column(Date, nullable=True)
    end_date = Column(Date, nullable=True)
    refill_date = Column(Date, nullable=True)
    total_quantity = Column(Integer, nullable=True)
    remaining_quantity = Column(Integer, nullable=True)
    is_active = Column(Boolean, default=True)
    prescription_id = Column(Integer, ForeignKey("prescriptions.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
