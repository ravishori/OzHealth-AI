from pydantic_settings import BaseSettings
from typing import List
import json


class Settings(BaseSettings):
    DATABASE_URL: str
    SYNC_DATABASE_URL: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    ANTHROPIC_API_KEY: str = ""
    OTP_EXPIRY_MINUTES: int = 10

    STORAGE_TYPE: str = "local"
    LOCAL_UPLOAD_DIR: str = "uploads"
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_S3_BUCKET: str = ""

    FIREBASE_CREDENTIALS_PATH: str = ""

    APP_NAME: str = "VitaPulse AI"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    CORS_ORIGINS: str = '["http://localhost:3000"]'

    # Gmail SMTP
    SMTP_EMAIL: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_SERVER: str = "smtp.gmail.com"
    SMTP_PORT: int = 587

    # Twilio
    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""
    TWILIO_PHONE_NUMBER: str = ""

    # Redis — used for caching and rate limiting
    REDIS_URL: str = "redis://localhost:6379/0"

    # Field-level encryption key (Fernet: URL-safe base64 of 32-byte key)
    # Generate with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
    ENCRYPTION_KEY: str = ""

    # Rate limiting — OTP send (per identifier per window)
    OTP_SEND_LIMIT: int = 20         # max OTP sends (relaxed for dev)
    OTP_SEND_WINDOW: int = 300       # seconds (5 min window)
    OTP_VERIFY_LIMIT: int = 20       # max failed verifications (relaxed for dev)
    OTP_VERIFY_WINDOW: int = 300     # seconds (5 min window)

    def get_cors_origins(self) -> List[str]:
        try:
            return json.loads(self.CORS_ORIGINS)
        except Exception:
            return ["*"]

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
