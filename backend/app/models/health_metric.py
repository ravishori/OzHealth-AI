from sqlalchemy import Column, Integer, String, ForeignKey, Float, DateTime, Text
from sqlalchemy.sql import func
from app.core.database import Base


class HealthMetric(Base):
    __tablename__ = "health_metrics"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    family_member_id = Column(Integer, ForeignKey("family_members.id", ondelete="SET NULL"), nullable=True)
    metric_type = Column(String(100), nullable=False, index=True)
    # blood_pressure_systolic, blood_pressure_diastolic, blood_sugar,
    # heart_rate, oxygen_level, weight, height, bmi, temperature
    value = Column(Float, nullable=False)
    value2 = Column(Float, nullable=True)  # For BP: diastolic
    unit = Column(String(50), nullable=True)
    notes = Column(Text, nullable=True)
    recorded_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    created_at = Column(DateTime(timezone=True), server_default=func.now())
