"""
OCR provider abstraction for prescription scan.

Providers are swappable; default composite:
  1) PDF embedded text (PyMuPDF) when present
  2) Tesseract image OCR when installed
  3) Optional sidecar fixture text (*.ocr.txt) for offline tests

No clinical interpretation — returns raw text + confidence only.
"""
from __future__ import annotations

import abc
import logging
import os
import re
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

from app.core.logging_config import ocr_log

logger = logging.getLogger(__name__)


@dataclass
class OcrResult:
    text: str
    # Provider-native score when available (Tesseract: typically 0–100).
    # API responses must normalize via ocr_confidence.normalize_confidence → 0.0..1.0.
    confidence: Optional[float] = None
    provider: str = "unknown"
    warnings: list[str] = field(default_factory=list)
    meta: dict[str, Any] = field(default_factory=dict)

    @property
    def available(self) -> bool:
        return bool(self.text and not self.text.startswith("[OCR"))


class OcrProvider(abc.ABC):
    name: str = "base"

    @abc.abstractmethod
    async def extract(self, path: str | Path) -> OcrResult:
        ...


class PdfTextOcrProvider(OcrProvider):
    """Extract embedded PDF text (not scanned-page OCR)."""

    name = "pymupdf_text"

    async def extract(self, path: str | Path) -> OcrResult:
        path = Path(path)
        try:
            import fitz
        except ImportError:
            return OcrResult(
                text="",
                provider=self.name,
                warnings=["PyMuPDF not installed"],
            )
        try:
            doc = fitz.open(str(path))
            text = "\n".join(page.get_text() for page in doc).strip()
            doc.close()
            ocr_log.info("PDF text extract OK path=%s chars=%d", path, len(text))
            return OcrResult(
                text=text,
                confidence=100.0 if text else None,
                provider=self.name,
                warnings=[] if text else ["PDF contained no extractable text"],
            )
        except Exception as e:
            ocr_log.error("PDF text extract failed: %s", e)
            return OcrResult(text="", provider=self.name, warnings=[str(e)])


class TesseractOcrProvider(OcrProvider):
    name = "tesseract"

    async def extract(self, path: str | Path) -> OcrResult:
        path = Path(path)
        try:
            import pytesseract
            from PIL import Image
        except ImportError:
            return OcrResult(
                text="[OCR not available - install tesseract-ocr and pytesseract]",
                provider=self.name,
                warnings=["pytesseract/Pillow not installed"],
            )

        try:
            img = Image.open(path)
            # Mean word confidence from image_to_data when available
            conf: Optional[float] = None
            try:
                data = pytesseract.image_to_data(img, lang="eng", output_type=pytesseract.Output.DICT)
                scores = [
                    float(c)
                    for c in data.get("conf", [])
                    if str(c) not in ("-1", "") and float(c) >= 0
                ]
                if scores:
                    conf = round(sum(scores) / len(scores), 1)
            except Exception:
                conf = None

            text = pytesseract.image_to_string(img, lang="eng").strip()
            ocr_log.info(
                "Tesseract OK path=%s chars=%d conf=%s", path, len(text), conf
            )
            return OcrResult(text=text, confidence=conf, provider=self.name)
        except Exception as e:
            err = type(e).__name__
            if "TesseractNotFound" in err or "tesseract" in str(e).lower():
                msg = "[OCR not available - tesseract binary not in PATH]"
                ocr_log.warning(msg)
                return OcrResult(
                    text=msg, provider=self.name, warnings=["tesseract not in PATH"]
                )
            ocr_log.error("Tesseract error: %s", e)
            return OcrResult(text="", provider=self.name, warnings=[str(e)])


class FixtureSidecarOcrProvider(OcrProvider):
    """
    Offline/test provider: if `<file>.ocr.txt` exists beside the image/PDF,
    return that text. Enables deterministic tests without a local tesseract binary.
    """

    name = "fixture_sidecar"

    async def extract(self, path: str | Path) -> OcrResult:
        path = Path(path)
        sidecar = path.with_suffix(path.suffix + ".ocr.txt")
        if not sidecar.exists():
            # also try stem.ocr.txt
            alt = path.with_name(path.stem + ".ocr.txt")
            sidecar = alt if alt.exists() else sidecar
        if not sidecar.exists():
            return OcrResult(text="", provider=self.name, warnings=["no sidecar"])
        text = sidecar.read_text(encoding="utf-8").strip()
        # Provider-native 0..100. Poor-quality fixtures intentionally lower.
        conf = 40.0 if "poor_quality" in path.name.lower() else 95.0
        return OcrResult(
            text=text,
            confidence=conf,
            provider=self.name,
            meta={"sidecar": str(sidecar)},
        )


class CompositeOcrProvider(OcrProvider):
    """
    Default provider chain for prescription OCR.
    PDF → try embedded text first; if empty and image/PDF scanned → tesseract;
    optionally allow fixture sidecars when AU_MED_OCR_ALLOW_FIXTURE=1 or tesseract missing.
    """

    name = "composite"

    def __init__(self, *, allow_fixture: Optional[bool] = None):
        env = os.environ.get("AU_MED_OCR_ALLOW_FIXTURE", "").strip().lower()
        if allow_fixture is None:
            allow_fixture = env in ("1", "true", "yes")
        self.allow_fixture = allow_fixture
        self.pdf = PdfTextOcrProvider()
        self.tesseract = TesseractOcrProvider()
        self.fixture = FixtureSidecarOcrProvider()

    async def extract(self, path: str | Path) -> OcrResult:
        path = Path(path)
        ext = path.suffix.lower()
        warnings: list[str] = []

        if ext == ".pdf":
            pdf_res = await self.pdf.extract(path)
            if pdf_res.text and len(pdf_res.text) >= 20:
                return pdf_res
            warnings.extend(pdf_res.warnings)
            # Rasterise first page via PyMuPDF then tesseract if possible
            raster = await self._rasterise_pdf_page(path)
            if raster:
                try:
                    tess = await self.tesseract.extract(raster)
                    if tess.available:
                        tess.warnings = warnings + tess.warnings
                        return tess
                    warnings.extend(tess.warnings)
                finally:
                    try:
                        os.unlink(raster)
                    except OSError:
                        pass

        if ext in {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp", ".pdf"}:
            tess = await self.tesseract.extract(path)
            if tess.available:
                tess.warnings = warnings + tess.warnings
                return tess
            warnings.extend(tess.warnings)

        if self.allow_fixture or any("tesseract" in w.lower() or "not in PATH" in w for w in warnings):
            fix = await self.fixture.extract(path)
            if fix.available:
                fix.warnings = warnings + [
                    "Used fixture sidecar OCR text (tesseract unavailable or AU_MED_OCR_ALLOW_FIXTURE=1)"
                ]
                return fix
            warnings.extend(fix.warnings)

        return OcrResult(
            text=tess.text if "tess" in locals() else "",
            provider=self.name,
            warnings=warnings or ["OCR produced no text"],
        )

    async def _rasterise_pdf_page(self, path: Path) -> Optional[str]:
        try:
            import fitz
        except ImportError:
            return None
        try:
            doc = fitz.open(str(path))
            if doc.page_count < 1:
                doc.close()
                return None
            page = doc.load_page(0)
            pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
            fd, out = tempfile.mkstemp(suffix=".png")
            os.close(fd)
            pix.save(out)
            doc.close()
            return out
        except Exception as e:
            ocr_log.warning("PDF rasterise failed: %s", e)
            return None


_default_provider: Optional[OcrProvider] = None


def get_ocr_provider() -> OcrProvider:
    global _default_provider
    if _default_provider is None:
        _default_provider = CompositeOcrProvider()
    return _default_provider


def set_ocr_provider(provider: OcrProvider) -> None:
    global _default_provider
    _default_provider = provider
