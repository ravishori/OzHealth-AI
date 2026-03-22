import logging
import os
from pathlib import Path
from app.core.config import settings

logger = logging.getLogger(__name__)


async def extract_prescription_text(file_path: str) -> str:
    """Extract text from prescription image/PDF using OCR."""
    try:
        # Local file path
        if file_path.startswith("/") or file_path.startswith("uploads"):
            local_path = file_path if os.path.isabs(file_path) else os.path.join(settings.LOCAL_UPLOAD_DIR, file_path)
        else:
            local_path = file_path

        ext = Path(local_path).suffix.lower()

        if ext == ".pdf":
            return await _extract_from_pdf(local_path)
        else:
            return await _extract_from_image(local_path)

    except Exception as e:
        logger.error(f"OCR error: {e}")
        return ""


async def _extract_from_image(path: str) -> str:
    try:
        import pytesseract
        from PIL import Image
        img = Image.open(path)
        text = pytesseract.image_to_string(img, lang="eng")
        return text.strip()
    except ImportError:
        logger.warning("pytesseract not installed. Install tesseract-ocr and pytesseract.")
        return "[OCR not available - install tesseract-ocr]"
    except Exception as e:
        logger.error(f"Image OCR error: {e}")
        return ""


async def _extract_from_pdf(path: str) -> str:
    try:
        import fitz  # PyMuPDF
        doc = fitz.open(path)
        text = ""
        for page in doc:
            text += page.get_text()
        return text.strip()
    except ImportError:
        try:
            # Fallback: convert PDF to image and OCR
            import pytesseract
            from PIL import Image
            import subprocess
            import tempfile

            with tempfile.TemporaryDirectory() as tmpdir:
                img_path = os.path.join(tmpdir, "page.png")
                subprocess.run(
                    ["pdftoppm", "-png", "-r", "200", path, os.path.join(tmpdir, "page")],
                    check=True, capture_output=True
                )
                images = sorted(Path(tmpdir).glob("*.png"))
                text = ""
                for img_file in images:
                    img = Image.open(str(img_file))
                    text += pytesseract.image_to_string(img) + "\n"
                return text.strip()
        except Exception as e:
            logger.error(f"PDF OCR fallback error: {e}")
            return "[PDF text extraction unavailable]"
    except Exception as e:
        logger.error(f"PDF OCR error: {e}")
        return ""
