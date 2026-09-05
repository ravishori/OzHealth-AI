from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text
from sqlalchemy.sql import func
from app.core.database import Base
from app.services.encryption_service import EncryptedText


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    email = Column(String(255), unique=True, nullable=True, index=True)
    phone = Column(String(20), unique=True, nullable=True, index=True)
    phone2 = Column(String(20), unique=True, nullable=True, index=True)
    age = Column(Integer, nullable=True)
    gender = Column(String(20), nullable=True)
    blood_group = Column(String(10), nullable=True)
    health_conditions = Column(EncryptedText, nullable=True)   # encrypted JSON array
    allergies = Column(EncryptedText, nullable=True)           # encrypted JSON array
    lifestyle_preferences = Column(EncryptedText, nullable=True)  # encrypted JSON object
    suburb = Column(String(100), nullable=True)
    city = Column(String(100), nullable=True)
    state = Column(String(100), nullable=True)
    postcode = Column(String(10), nullable=True)
    fcm_token = Column(String(500), nullable=True)
    is_active = Column(Boolean, default=True)
    is_verified = Column(Boolean, default=False)
    profile_image_url = Column(String(500), nullable=True)
    # Incremented on logout — JWT claim "tv" must match for access/refresh.
    token_version = Column(Integer, nullable=False, server_default="0", default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
