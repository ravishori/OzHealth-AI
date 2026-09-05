"""
Minimum prescription OCR pipeline:
  upload → OCR → extract medicine lines → catalog medicine search → candidates

No diagnosis, interactions, chatbot, or medical advice.
"""
from __future__ import annotations

import logging
import os
import re
import tempfile
import uuid
from pathlib import Path
from typing import Any, Optional

from fastapi import UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.catalog_medicine_search_service import CatalogMedicineSearchService
from app.services.ocr_confidence import build_ocr_confidence_payload
from app.services.ocr_provider import OcrResult, get_ocr_provider
from app.services.prescription_medicine_extractor import (
    ExtractedMedicineLine,
    extract_medicine_candidates,
)

logger = logging.getLogger(__name__)

ALLOWED_EXTS = {"jpg", "jpeg", "png", "pdf"}
ALLOWED_MIME = {
    "image/jpeg",
    "image/jpg",
    "image/png",
    "application/pdf",
    "application/x-pdf",
}
MAX_BYTES = 10 * 1024 * 1024  # 10 MB
_JPEG = b"\xff\xd8\xff"
_PNG = b"\x89PNG\r\n\x1a\n"
_PDF = b"%PDF"


class PrescriptionUploadError(ValueError):
    pass


def _safe_ext(filename: Optional[str]) -> str:
    name = Path(filename or "upload.bin").name
    # strip path components
    name = name.replace("\\", "/").split("/")[-1]
    if "." not in name:
        raise PrescriptionUploadError("File must have an extension")
    ext = name.rsplit(".", 1)[-1].lower()
    if ext not in ALLOWED_EXTS:
        raise PrescriptionUploadError(
            f"Unsupported file type .{ext}. Allowed: {sorted(ALLOWED_EXTS)}"
        )
    return ext


def _validate_magic(ext: str, content: bytes) -> None:
    if len(content) < 8:
        raise PrescriptionUploadError("File is empty or too small")
    if ext in ("jpg", "jpeg") and content[:3] != _JPEG:
        raise PrescriptionUploadError("Content is not a valid JPEG")
    if ext == "png" and content[:8] != _PNG:
        raise PrescriptionUploadError("Content is not a valid PNG")
    if ext == "pdf" and content[:4] != _PDF:
        raise PrescriptionUploadError("Content is not a valid PDF")


async def save_temp_upload(file: UploadFile) -> tuple[Path, str, int]:
    """Validate and write upload to a temporary file. Caller must delete."""
    ext = _safe_ext(file.filename)
    content = await file.read()
    if len(content) > MAX_BYTES:
        raise PrescriptionUploadError(
            f"File too large (max {MAX_BYTES // (1024 * 1024)} MB)"
        )
    ctype = (file.content_type or "").split(";")[0].strip().lower()
    if ctype and ctype not in ALLOWED_MIME and ctype != "application/octet-stream":
        raise PrescriptionUploadError(f"Unsupported MIME type: {ctype}")
    _validate_magic(ext, content)

    fd, tmp = tempfile.mkstemp(prefix="rx_ocr_", suffix=f".{ext}")
    os.close(fd)
    path = Path(tmp)
    path.write_bytes(content)
    return path, ext, len(content)


def _match_reason(extracted: ExtractedMedicineLine, candidate: dict[str, Any]) -> str:
    reasons = []
    en = (extracted.extracted_name or "").lower()
    cn = (candidate.get("name") or "").lower()
    cg = (candidate.get("generic_name") or "").lower()
    if en and (en == cn or en in cn or cn.startswith(en)):
        reasons.append("name")
    if en and cg and (en in cg or cg in en):
        reasons.append("generic")
    es = (extracted.extracted_strength or "").lower().replace(" ", "")
    cs = (str(candidate.get("strength") or "")).lower().replace(" ", "")
    if es and cs and (es in cs or cs in es):
        reasons.append("strength")
    if candidate.get("artg_number"):
        reasons.append("catalog_artg")
    if candidate.get("pbs_code"):
        reasons.append("catalog_pbs")
    return "+".join(reasons) if reasons else "catalog_search"


class PrescriptionOcrPipeline:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.search = CatalogMedicineSearchService(db)
        self.ocr = get_ocr_provider()

    async def process_file(
        self,
        path: Path,
        *,
        original_filename: Optional[str] = None,
        search_limit: int = 5,
    ) -> dict[str, Any]:
        prescription_id = str(uuid.uuid4())
        ocr: OcrResult = await self.ocr.extract(path)
        # Do not invent medicine lines from unavailable/placeholder OCR messages.
        extracted = (
            extract_medicine_candidates(ocr.text) if ocr.available else []
        )

        medicines_out: list[dict[str, Any]] = []
        matched = 0
        unmatched = 0

        for line in extracted:
            q = line.extracted_name
            if line.extracted_strength:
                q = f"{q} {line.extracted_strength}"
            search = await self.search.search(q, limit=search_limit)
            # If no hits with strength, retry name-only
            if not search.get("results") and line.extracted_strength:
                search = await self.search.search(line.extracted_name, limit=search_limit)

            candidates = []
            for c in search.get("results") or []:
                candidates.append(
                    {
                        "medicine_id": c.get("id"),
                        "name": c.get("name"),
                        "generic_name": c.get("generic_name"),
                        "strength": c.get("strength"),
                        "dosage_form": c.get("dosage_form"),
                        "ARTG": c.get("artg_number"),
                        "PBS": c.get("pbs_code"),
                        "match_reason": _match_reason(line, c),
                        "source": "database",
                        "confirmed_medicine": True,
                    }
                )

            if candidates:
                matched += 1
            else:
                unmatched += 1

            medicines_out.append(
                {
                    "extracted_name": line.extracted_name,
                    "extracted_strength": line.extracted_strength,
                    "extracted_frequency": line.extracted_frequency,
                    "extracted_route": line.extracted_route,
                    "source_line": line.source_line,
                    "source": "ocr_extracted",
                    "confirmed_medicine": False,
                    "candidates": candidates,
                    "match_status": "MATCHED" if candidates else "UNMATCHED",
                }
            )

        conf_payload = build_ocr_confidence_payload(
            ocr.confidence,
            available=ocr.available,
            unmatched_count=unmatched,
        )
        warnings = list(ocr.warnings)
        if not ocr.available:
            warnings.append("OCR unavailable or produced no usable text")
        if conf_payload["low_confidence"]:
            warnings.append(
                "OCR confidence is low or missing — review required before save"
            )

        return {
            "prescription_id": prescription_id,
            "original_filename": Path(original_filename or path.name).name,
            "ocr": {
                "text": ocr.text if ocr.available else "",
                "confidence": conf_payload["confidence"],
                "confidence_scale": conf_payload["confidence_scale"],
                "review_threshold": conf_payload["review_threshold"],
                "low_confidence": conf_payload["low_confidence"],
                "needs_review": conf_payload["needs_review"],
                "available": conf_payload["available"],
                "provider": ocr.provider,
                "warnings": warnings,
                "source": "ocr_extracted",
            },
            "medicines": medicines_out,
            "summary": {
                "extracted_count": len(extracted),
                "matched_count": matched,
                "unmatched_count": unmatched,
                "ocr_available": ocr.available,
                "low_confidence": conf_payload["low_confidence"],
                "needs_review": conf_payload["needs_review"],
            },
            "safety": {
                "disclaimer": (
                    "OCR text is unconfirmed extraction. Database candidates are "
                    "catalog matches only — not a clinical confirmation, diagnosis, "
                    "or medical advice. Always verify with a registered practitioner."
                ),
                "ocr_vs_database": (
                    "Fields under each medicine marked source=ocr_extracted are from "
                    "OCR only. Candidates with confirmed_medicine=true come from the "
                    "medicine database search API."
                ),
                "permanent_storage": False,
                "requires_review_acknowledgement": conf_payload["needs_review"],
            },
        }
