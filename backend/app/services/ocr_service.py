"""Backward-compatible OCR helpers — delegates to OcrProvider abstraction. """
import logging
import os

from app.core.config import settings
from app.core.logging_config import ocr_log
from app.services.ocr_provider import get_ocr_provider

logger = logging.getLogger(__name__)


async def extract_prescription_text(file_path: str) -> str:
    """Extract text from a prescription image or PDF using the configured OCR provider."""
    try:
        if file_path.startswith("/") or file_path.startswith("uploads"):
            local_path = (
                file_path
                if os.path.isabs(file_path)
                else os.path.join(settings.LOCAL_UPLOAD_DIR, file_path)
            )
        else:
            local_path = file_path

        ocr_log.debug("OCR request path=%s", local_path)
        result = await get_ocr_provider().extract(local_path)
        return result.text or ""
    except Exception as e:
        ocr_log.error("OCR error path=%s: %s: %s", file_path, type(e).__name__, e)
        return ""


async def extract_prescription_ocr(file_path: str):
    """Return full OcrResult (text + confidence + provider)."""
    return await get_ocr_provider().extract(file_path)
