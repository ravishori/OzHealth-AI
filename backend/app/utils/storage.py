import os
import uuid
import aiofiles
import logging
from pathlib import Path
from fastapi import UploadFile
from app.core.config import settings

logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {"pdf", "jpg", "jpeg", "png", "heic"}
MAX_FILE_SIZE = 20 * 1024 * 1024  # 20 MB

# Resolve the upload root once at module load time
_UPLOAD_ROOT = Path(settings.LOCAL_UPLOAD_DIR).resolve()


def _safe_path(folder: str, filename: str) -> Path:
    """
    Build a safe file path under _UPLOAD_ROOT.
    Raises ValueError if the resolved path escapes the upload root
    (path traversal protection).
    """
    # Sanitise folder: strip leading slashes and reject any '..' components
    clean_folder = "/".join(
        part for part in Path(folder).parts if part not in ("", "..", ".")
    )
    resolved = (_UPLOAD_ROOT / clean_folder / filename).resolve()

    if not str(resolved).startswith(str(_UPLOAD_ROOT)):
        raise ValueError(f"Path traversal detected in folder: {folder!r}")

    return resolved


async def save_file(file: UploadFile, folder: str = "uploads") -> str:
    """
    Save an uploaded file under LOCAL_UPLOAD_DIR/<folder>/<uuid>.<ext>.

    Returns the relative path from LOCAL_UPLOAD_DIR (used as file_url in DB).
    Raises ValueError on invalid extension, oversized file, or path traversal.
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

    # Return path relative to upload root (used as file_url in DB and served via /uploads)
    return str(file_path.relative_to(_UPLOAD_ROOT))
