"""Read-only ORM models for medicine search enrichment (no schema changes)."""
from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    Date,
    DateTime,
    Integer,
    Numeric,
    SmallInteger,
    String,
    Text,
)
from sqlalchemy.sql import func

from app.core.database import Base


class MedicineIngredientStrength(Base):
    __tablename__ = "medicine_ingredient_strengths"

    ingredient_strength_id = Column(BigInteger, primary_key=True)
    medicine_id = Column(Integer, nullable=False, index=True)
    ingredient_name = Column(String(500), nullable=False)
    ingredient_role = Column(String(30), nullable=False, server_default="ACTIVE")
    position = Column(SmallInteger, nullable=False, server_default="0")
    strength_value = Column(Numeric(20, 6), nullable=True)
    strength_unit = Column(String(20), nullable=True)
    source = Column(String(30), nullable=True)
    confidence = Column(Numeric(5, 2), nullable=True)


class PbsListing(Base):
    __tablename__ = "pbs_listings"

    pbs_listing_id = Column(BigInteger, primary_key=True)
    medicine_id = Column(Integer, nullable=True, index=True)
    pbs_code = Column(String(50), nullable=True, index=True)
    program_code = Column(String(20), nullable=True)
    restriction_level = Column(String(50), nullable=True)
    restriction_text = Column(Text, nullable=True)
    authority_required = Column(Boolean, nullable=True, server_default="false")
    max_quantity = Column(Integer, nullable=True)
    repeats_allowed = Column(Integer, nullable=True)
    patient_price = Column(Numeric(10, 2), nullable=True)
    concession_price = Column(Numeric(10, 2), nullable=True)
    safety_net_price = Column(Numeric(10, 2), nullable=True)
    effective_date = Column(Date, nullable=True)
    end_date = Column(Date, nullable=True)
    is_active = Column(Boolean, nullable=True, server_default="true")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
