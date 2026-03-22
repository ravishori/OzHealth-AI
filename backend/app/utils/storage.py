import os
import uuid
import aiofiles
from fastapi import UploadFile
from app.core.config import settings

ALLOWED_EXTENSIONS = {"pdf", "jpg", "jpeg", "png", "heic"}
MAX_FILE_SIZE = 20 * 1024 * 1024  # 20 MB


async def save_file(file: UploadFile, folder: str = "uploads") -> str:
    """Save uploaded file locally (or to S3 in production)."""
    ext = (file.filename or "file").rsplit(".", 1)[-1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise ValueError(f"File type .{ext} not allowed. Allowed: {ALLOWED_EXTENSIONS}")

    filename = f"{uuid.uuid4()}.{ext}"
    dir_path = os.path.join(settings.LOCAL_UPLOAD_DIR, folder)
    os.makedirs(dir_path, exist_ok=True)

    file_path = os.path.join(dir_path, filename)

    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise ValueError(f"File too large. Maximum size: {MAX_FILE_SIZE // (1024*1024)}MB")

    async with aiofiles.open(file_path, "wb") as f:
        await f.write(content)

    return file_path
