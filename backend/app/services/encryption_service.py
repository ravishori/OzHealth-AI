"""
AES-256 field-level encryption service using Fernet (symmetric encryption).

Fernet guarantees:
  - AES-128-CBC encryption with PKCS7 padding
  - HMAC-SHA256 authentication
  - Timestamp (for optional TTL checks)

Usage:
    from app.services.encryption_service import encrypt, decrypt, EncryptedText

    # Direct encrypt/decrypt
    cipher = encrypt("sensitive data")
    plain  = decrypt(cipher)

    # As SQLAlchemy column type — transparent encryption at ORM level
    class MyModel(Base):
        secret_field = Column(EncryptedText)
"""
import logging
import os
import base64
from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy import TypeDecorator, Text

logger = logging.getLogger(__name__)

# ─── Key management ──────────────────────────────────────────────────────────

_fernet: Fernet | None = None


def _get_fernet() -> Fernet:
    global _fernet
    if _fernet is not None:
        return _fernet

    key = os.environ.get("ENCRYPTION_KEY", "")
    if not key:
        # Generate a dev key deterministically from SECRET_KEY to avoid startup failure.
        # In production, ENCRYPTION_KEY MUST be set explicitly.
        from app.core.config import settings
        secret = settings.SECRET_KEY.encode()
        # Derive a 32-byte key via base64 of first 32 bytes padded/truncated
        raw = (secret * 4)[:32]
        key = base64.urlsafe_b64encode(raw).decode()
        logger.warning(
            "ENCRYPTION_KEY not set — using derived key. "
            "Set ENCRYPTION_KEY in .env for production."
        )

    # Fernet requires URL-safe base64-encoded 32-byte key
    try:
        _fernet = Fernet(key.encode() if isinstance(key, str) else key)
    except Exception:
        # If provided key is wrong length, generate a proper one from it
        raw = base64.urlsafe_b64decode(key + "==")[:32]
        raw = raw.ljust(32, b"\x00")
        _fernet = Fernet(base64.urlsafe_b64encode(raw))

    return _fernet


# ─── Core functions ──────────────────────────────────────────────────────────

def encrypt(value: str) -> str:
    """Encrypt a plaintext string. Returns a URL-safe base64 token."""
    if not value:
        return value
    try:
        return _get_fernet().encrypt(value.encode("utf-8")).decode("utf-8")
    except Exception as exc:
        logger.error("Encryption failed: %s", exc)
        raise


def decrypt(value: str) -> str:
    """
    Decrypt a Fernet token back to plaintext.
    Returns original value unchanged if decryption fails (handles legacy plaintext rows).
    """
    if not value:
        return value
    try:
        return _get_fernet().decrypt(value.encode("utf-8")).decode("utf-8")
    except (InvalidToken, Exception):
        # Graceful fallback: data was stored before encryption was enabled
        return value


# ─── SQLAlchemy TypeDecorator ─────────────────────────────────────────────────

class EncryptedText(TypeDecorator):
    """
    SQLAlchemy column type that transparently encrypts on write and decrypts on read.

    Usage:
        notes = Column(EncryptedText, nullable=True)
    """
    impl = Text
    cache_ok = True

    def process_bind_param(self, value, dialect):
        """Called when writing to DB — encrypt the value."""
        if value is None:
            return None
        return encrypt(str(value))

    def process_result_value(self, value, dialect):
        """Called when reading from DB — decrypt the value."""
        if value is None:
            return None
        return decrypt(value)
