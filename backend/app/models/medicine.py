from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean
from sqlalchemy.sql import func
from app.core.database import Base


class Medicine(Base):
    __tablename__ = "medicines"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(500), nullable=False, index=True)
    generic_name = Column(String(500), nullable=True, index=True)
    brand_names = Column(Text, nullable=True)  # JSON array
    composition = Column(Text, nullable=True)
    drug_class = Column(String(255), nullable=True)
    dosage_forms = Column(Text, nullable=True)  # JSON array
    standard_dosage = Column(Text, nullable=True)
    side_effects = Column(Text, nullable=True)
    interactions = Column(Text, nullable=True)
    contraindications = Column(Text, nullable=True)
    warnings = Column(Text, nullable=True)
    storage_instructions = Column(Text, nullable=True)
    barcode = Column(String(100), nullable=True, index=True)
    tga_registered = Column(Boolean, default=False)  # TGA = Therapeutic Goods Administration AU
    schedule = Column(String(50), nullable=True)  # S2, S3, S4, S8 (AU schedule)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
