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
    PBS_SUBSCRIPTION_KEY: str = ""

    ANTHROPIC_API_KEY: str = ""
    OTP_EXPIRY_MINUTES: int = 10

    STORAGE_TYPE: str = "local"
    LOCAL_UPLOAD_DIR: str = "uploads"
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_S3_BUCKET: str = ""

    FIREBASE_CREDENTIALS_PATH: str = ""

    APP_NAME: str = "HealthNest"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    CORS_ORIGINS: str = '["http://localhost:3000"]'

    # Gmail SMTP — set via environment / .env only (never commit secrets)
    SMTP_EMAIL: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_SERVER: str = "smtp.gmail.com"
    SMTP_PORT: int = 587

    # Twilio — set via environment / .env only
    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""
    TWILIO_PHONE_NUMBER: str = ""

    # Redis — used for caching and rate limiting
    REDIS_URL: str = "redis://localhost:6379/0"

    # Nearby (OSM Overpass / Nominatim) — HN-NEARBY-001 bounded timeouts
    NEARBY_OVERPASS_TIMEOUT_SECONDS: float = 12.0   # per mirror httpx timeout
    NEARBY_OVERPASS_OVERALL_SECONDS: float = 22.0    # hard budget for all mirrors
    NEARBY_OVERPASS_QL_TIMEOUT: int = 10             # Overpass QL [timeout:N]
    NEARBY_NOMINATIM_TIMEOUT_SECONDS: float = 8.0    # per Nominatim request

    # Field-level encryption key (Fernet: URL-safe base64 of 32-byte key)
    # Generate with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
    ENCRYPTION_KEY: str = ""

    # Developer alert email recipients (comma-separated)
    DEVELOPER_EMAILS: str = ""

    # Rate limiting — OTP send (per identifier per window)
    OTP_SEND_LIMIT: int = 20         # max OTP sends (relaxed for dev)
    OTP_SEND_WINDOW: int = 300       # seconds (5 min window)
    OTP_VERIFY_LIMIT: int = 20       # max failed verifications (relaxed for dev)
    OTP_VERIFY_WINDOW: int = 300     # seconds (5 min window)

    # ── ePrescription — eRx Script Exchange (NPDS) ───────────────────────────
    # Set EPRESCRIPTION_MOCK_MODE=false and supply ERX_API_KEY for live integration.
    # Obtain credentials from: https://erx.com.au
    # NOTE: MediSecure is discontinued (data breach 2024, liquidated June 2024).
    #       Only eRx Script Exchange (NPDS) is supported.
    ERX_API_URL:             str  = "https://api.erx.com.au/v1"
    ERX_API_KEY:             str  = ""
    EPRESCRIPTION_MOCK_MODE: bool = True   # True = mock data, no real API calls

    def get_developer_emails(self) -> List[str]:
        """Parse comma-separated developer email list."""
        return [e.strip() for e in self.DEVELOPER_EMAILS.split(",") if e.strip()]

    def get_cors_origins(self) -> List[str]:
        """Return explicit CORS origins. Never returns '*' (incompatible with credentials)."""
        try:
            parsed = json.loads(self.CORS_ORIGINS)
            origins = [str(o).strip() for o in parsed if str(o).strip() and str(o).strip() != "*"]
        except Exception:
            origins = []
        if not origins:
            return [
                "http://localhost:3000",
                "http://127.0.0.1:3000",
                "http://localhost:8080",
                "http://127.0.0.1:8080",
            ]
        return origins

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
