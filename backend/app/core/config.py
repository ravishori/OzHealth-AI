from pydantic_settings import BaseSettings
from typing import List, Optional
import json
import logging

_logger = logging.getLogger(__name__)


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
    # development | staging | production | test
    ENVIRONMENT: str = "development"
    # Optional override. Hosted (staging/production) never auto-creates schema.
    # Unset → create_all only when ENVIRONMENT is development/test.
    AUTO_CREATE_TABLES: Optional[bool] = None
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

    def environment_name(self) -> str:
        return (self.ENVIRONMENT or "development").strip().lower()

    def is_hosted_environment(self) -> bool:
        return self.environment_name() in {"staging", "production"}

    def should_auto_create_tables(self) -> bool:
        """
        Schema must come from Alembic in staging/production.
        create_all is allowed only for local development/test convenience.
        """
        if self.is_hosted_environment():
            return False
        if self.AUTO_CREATE_TABLES is not None:
            return bool(self.AUTO_CREATE_TABLES)
        return self.environment_name() in {"development", "test", "dev"}

    def validate_for_startup(self) -> None:
        """
        Fail fast on hosted misconfiguration. Never logs secret values.
        """
        env = self.environment_name()
        missing: List[str] = []
        if not self.DATABASE_URL:
            missing.append("DATABASE_URL")
        if not self.SYNC_DATABASE_URL:
            missing.append("SYNC_DATABASE_URL")
        if not self.SECRET_KEY:
            missing.append("SECRET_KEY")
        if missing:
            raise RuntimeError(
                f"Missing required settings for ENVIRONMENT={env}: {', '.join(missing)}"
            )

        if not self.is_hosted_environment():
            return

        problems: List[str] = []
        if self.DEBUG:
            problems.append("DEBUG must be false in staging/production")
        if not (self.ENCRYPTION_KEY or "").strip():
            problems.append("ENCRYPTION_KEY must be set in staging/production")
        weak_secret = self.SECRET_KEY.strip().lower() in {
            "",
            "changeme",
            "secret",
            "replace_with_a_long_random_secret",
            "test-secret-key-for-unit-tests-only",
        }
        if weak_secret or len(self.SECRET_KEY.strip()) < 32:
            problems.append("SECRET_KEY must be a strong non-placeholder value (len>=32)")
        if self.AUTO_CREATE_TABLES is True:
            problems.append(
                "AUTO_CREATE_TABLES cannot be enabled in staging/production "
                "(use alembic upgrade head)"
            )
        if problems:
            raise RuntimeError(
                "Invalid staging/production configuration: " + "; ".join(problems)
            )

        _logger.info(
            "Hosted environment startup validation passed env=%s auto_create_tables=%s",
            env,
            self.should_auto_create_tables(),
        )

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
