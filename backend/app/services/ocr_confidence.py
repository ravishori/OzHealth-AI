"""
OCR confidence contract (HN-OCR-003).

Canonical API / Flutter representation: 0.0 .. 1.0 (unit interval).
Providers (Tesseract) may produce native 0..100 scores; normalize once at the
API boundary — never compare 0..100 against a 0..1 threshold.
"""
from __future__ import annotations

from typing import Any, Optional

# Product threshold: below this → requires review (equal-to is OK).
OCR_REVIEW_THRESHOLD: float = 0.60


def normalize_confidence(raw: Any) -> Optional[float]:
    """
    Convert a provider or client confidence value to 0.0..1.0.

    Returns None for missing/invalid values (callers must treat as needs-review).
    Values > 1.0 are treated as percent (e.g. 95 → 0.95).
    """
    if raw is None:
        return None
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return None
    if value != value:  # NaN
        return None
    if value < 0:
        return None
    if value > 1.0:
        value = value / 100.0
    if value > 1.0:
        return None
    return round(value, 4)


def is_low_confidence(
    confidence: Optional[float],
    *,
    threshold: float = OCR_REVIEW_THRESHOLD,
) -> bool:
    """
    True when OCR confidence is missing/invalid or strictly below threshold.

    Missing confidence fails closed (requires review).
    """
    if confidence is None:
        return True
    return confidence < threshold


def build_ocr_confidence_payload(
    raw_confidence: Any,
    *,
    available: bool,
    unmatched_count: int = 0,
) -> dict[str, Any]:
    """Structured confidence fields for OCR API responses."""
    unit = normalize_confidence(raw_confidence)
    low = (not available) or is_low_confidence(unit)
    needs_review = low or unmatched_count > 0
    return {
        "confidence": unit,
        "confidence_scale": "unit",  # canonical 0.0..1.0
        "review_threshold": OCR_REVIEW_THRESHOLD,
        "low_confidence": low,
        "needs_review": needs_review,
        "available": available,
    }
