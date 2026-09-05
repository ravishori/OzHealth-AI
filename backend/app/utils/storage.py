import os
import uuid
import aiofiles
import logging
from pathlib import Path
from fastapi import UploadFile
from cryptography.fernet import InvalidToken

from app.core.config import settings
from app.services.encryption_service import (
    encrypt_bytes,
    decrypt_bytes,
    is_encrypted_record_blob,
)

logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {"pdf", "jpg", "jpeg", "png", "heic"}
MAX_FILE_SIZE = 20 * 1024 * 1024  # 20 MB

# Profile photo constraints
_PROFILE_ALLOWED_EXTS  = {"jpg", "jpeg", "png"}
_PROFILE_MAX_SIZE      = 2 * 1024 * 1024      # 2 MB
_JPEG_MAGIC            = b"\xff\xd8\xff"       # first 3 bytes of every JPEG
_PNG_MAGIC             = b"\x89PNG\r\n\x1a\n"  # first 8 bytes of every PNG

# Resolve the upload root once at module load time
_UPLOAD_ROOT = Path(settings.LOCAL_UPLOAD_DIR).resolve()


def get_upload_root() -> Path:
    """Current upload root (patchable in tests)."""
    return _UPLOAD_ROOT


def _safe_path(folder: str, filename: str) -> Path:
    """
    Build a safe file path under upload root.
    Raises ValueError if the resolved path escapes the upload root
    (path traversal protection).
    """
    clean_folder = "/".join(
        part for part in Path(folder).parts if part not in ("", "..", ".")
    )
    root = get_upload_root()
    resolved = (root / clean_folder / filename).resolve()

    if not str(resolved).startswith(str(root)):
        raise ValueError(f"Path traversal detected in folder: {folder!r}")

    return resolved


async def save_file(file: UploadFile, folder: str = "uploads") -> str:
    """
    Save an uploaded file under LOCAL_UPLOAD_DIR/<folder>/<uuid>.<ext> as plaintext.

    Used for non-medical-record uploads. Medical records must use
    save_encrypted_medical_file (HN-RECORD-009).
    """
    ext = (file.filename or "file").rsplit(".", 1)[-1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise ValueError(f"File type .{ext} not allowed. Allowed: {sorted(ALLOWED_EXTENSIONS)}")

    filename = f"{uuid.uuid4()}.{ext}"

    try:
        file_path = _safe_path(folder, filename)
    except ValueError as exc:
        logger.warning("Path traversal attempt blocked: %s", exc)
        raise

    file_path.parent.mkdir(parents=True, exist_ok=True)

    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise ValueError(f"File too large. Maximum size: {MAX_FILE_SIZE // (1024 * 1024)} MB")

    async with aiofiles.open(file_path, "wb") as f:
        await f.write(content)

    return file_path.relative_to(get_upload_root()).as_posix()


async def save_encrypted_medical_file(file: UploadFile, folder: str) -> str:
    """
    HN-RECORD-009 — encrypt medical-record file bytes before writing to disk.

    Encrypts in memory first; only ciphertext is written. On encryption failure,
    no file is created (fail closed).
    """
    ext = (file.filename or "file").rsplit(".", 1)[-1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise ValueError(f"File type .{ext} not allowed. Allowed: {sorted(ALLOWED_EXTENSIONS)}")

    filename = f"{uuid.uuid4()}.{ext}"

    try:
        file_path = _safe_path(folder, filename)
    except ValueError as exc:
        logger.warning("Path traversal attempt blocked: %s", exc)
        raise

    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise ValueError(f"File too large. Maximum size: {MAX_FILE_SIZE // (1024 * 1024)} MB")

    try:
        ciphertext = encrypt_bytes(content)
    except Exception:
        raise

    file_path.parent.mkdir(parents=True, exist_ok=True)
    async with aiofiles.open(file_path, "wb") as f:
        await f.write(ciphertext)

    logger.info(
        "Encrypted medical file saved name=%s cipher_bytes=%d",
        file_path.name,
        len(ciphertext),
    )
    return file_path.relative_to(get_upload_root()).as_posix()


def read_medical_record_bytes(rel_path: str) -> bytes:
    """
    Read a medical-record object from disk.

    - Encrypted blobs (HNREC1…): decrypt and return plaintext bytes.
    - Legacy plaintext: return as-is (compatibility; no auto-rewrite).
    - Corrupt / wrong-key ciphertext: raise ValueError (fail closed).
    """
    if not rel_path:
        raise FileNotFoundError("empty path")

    root = get_upload_root()
    target = (root / rel_path).resolve()
    if not str(target).startswith(str(root)):
        raise ValueError("Path traversal blocked")
    if not target.is_file():
        raise FileNotFoundError(rel_path)

    raw = target.read_bytes()
    if is_encrypted_record_blob(raw):
        try:
            return decrypt_bytes(raw)
        except InvalidToken as exc:
            raise ValueError("decrypt_failed") from exc
        except Exception as exc:
            raise ValueError("decrypt_failed") from exc
    return raw


async def save_profile_image(file: UploadFile, folder: str = "uploads") -> str:
    """
    Save a profile photo with strict security validation:
      - Allowed formats: JPG / PNG only
      - Maximum size: 2 MB
      - Magic-byte MIME validation (prevents extension spoofing)
      - Path traversal protection
    """
    ext = (file.filename or "file").rsplit(".", 1)[-1].lower()
    if ext not in _PROFILE_ALLOWED_EXTS:
        raise ValueError("Only JPG and PNG files are allowed for profile photos.")

    content = await file.read()

    if len(content) == 0:
        raise ValueError("Uploaded file is empty.")

    if len(content) > _PROFILE_MAX_SIZE:
        size_mb = len(content) / (1024 * 1024)
        raise ValueError(f"Profile photo must be under 2 MB (got {size_mb:.1f} MB).")

    if ext in ("jpg", "jpeg"):
        if content[:3] != _JPEG_MAGIC:
            raise ValueError("File content does not match a valid JPEG image.")
    elif ext == "png":
        if content[:8] != _PNG_MAGIC:
            raise ValueError("File content does not match a valid PNG image.")

    filename = f"{uuid.uuid4()}.{ext}"

    try:
        file_path = _safe_path(folder, filename)
    except ValueError as exc:
        logger.warning("Path traversal attempt blocked: %s", exc)
        raise

    file_path.parent.mkdir(parents=True, exist_ok=True)

    async with aiofiles.open(file_path, "wb") as f:
        await f.write(content)

    logger.info("Profile image saved: %s (%d bytes)", file_path.name, len(content))
    return file_path.relative_to(get_upload_root()).as_posix()


def delete_file(rel_path: str | None) -> None:
    """
    Silently delete a file given its relative path from the upload root.
    Ignores errors (file not found, permissions, etc.) — non-critical cleanup.
    """
    if not rel_path:
        return
    try:
        root = get_upload_root()
        target = (root / rel_path).resolve()
        if str(target).startswith(str(root)) and target.is_file():
            target.unlink()
            logger.info("Deleted upload file: %s", rel_path)
    except Exception as exc:
        logger.warning(
            "Could not delete upload file %r: %s", rel_path, type(exc).__name__
        )
