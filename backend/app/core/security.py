from datetime import datetime, timedelta, timezone
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from app.core.config import settings
import random
import string
import uuid

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def create_access_token(
    data: dict,
    expires_delta: Optional[timedelta] = None,
    *,
    token_version: int = 0,
) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({
        "exp": expire,
        "type": "access",
        "tv": int(token_version),
    })
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(data: dict, *, token_version: int = 0) -> str:
    """
    Build a refresh JWT.

    HN-AUTH-011: every refresh token embeds a unique ``jti`` so the server can
    atomically consume/rotate one token without invalidating other devices.
    """
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    # Caller may supply jti for tests; otherwise mint a new opaque id.
    jti = to_encode.pop("jti", None) or str(uuid.uuid4())
    to_encode.update({
        "exp": expire,
        "type": "refresh",
        "tv": int(token_version),
        "jti": jti,
    })
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def refresh_token_ttl_seconds() -> int:
    """TTL for server-side refresh jti bindings (matches JWT refresh lifetime)."""
    return int(settings.REFRESH_TOKEN_EXPIRE_DAYS) * 24 * 60 * 60


def decode_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload
    except JWTError:
        return {}


def generate_otp(length: int = 6) -> str:
    return "".join(random.choices(string.digits, k=length))


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


# OTP hashing — use HMAC-SHA256 (bcrypt is overkill for short-lived 6-digit codes
# that are already protected by rate limiting and 10-minute expiry)
import hashlib
import hmac as _hmac


def hash_otp(otp_code: str) -> str:
    """
    Hash an OTP code with HMAC-SHA256 keyed by SECRET_KEY.
    Returns a hex digest that is safe to store in the DB.
    """
    key = settings.SECRET_KEY.encode("utf-8")
    return _hmac.new(key, otp_code.encode("utf-8"), hashlib.sha256).hexdigest()


def verify_otp(plain_otp: str, stored_hash: str) -> bool:
    """Constant-time comparison of OTP hash to prevent timing attacks."""
    expected = hash_otp(plain_otp)
    return _hmac.compare_digest(expected, stored_hash)
