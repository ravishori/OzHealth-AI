"""HN-OCR-003 — OCR confidence contract + safety gate (OCR-S6-01..12)."""
from __future__ import annotations

import inspect
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.api.routes import prescriptions as rx
from app.core.database import get_db
from app.core.deps import get_current_user
from app.services import ocr_confidence as conf_mod
from app.services.ocr_confidence import (
    OCR_REVIEW_THRESHOLD,
    build_ocr_confidence_payload,
    is_low_confidence,
    normalize_confidence,
)
from app.services.ocr_provider import OcrResult
from app.services.prescription_ocr_pipeline import PrescriptionOcrPipeline


def _user(uid: int = 1):
    return SimpleNamespace(
        id=uid,
        email="a@example.com",
        is_active=True,
        allergies=None,
    )


@pytest.fixture
def anyio_backend():
    return "asyncio"


# ─── OCR-S6-01..05 unit confidence ───────────────────────────────────────────


def test_ocr_s6_01_confidence_scale_95_to_unit():
    assert normalize_confidence(95) == 0.95
    assert normalize_confidence(95.0) == 0.95
    assert normalize_confidence(0.95) == 0.95


def test_ocr_s6_02_high_confidence_not_low():
    unit = normalize_confidence(95)
    assert unit is not None
    assert unit >= OCR_REVIEW_THRESHOLD
    assert is_low_confidence(unit) is False
    payload = build_ocr_confidence_payload(95, available=True, unmatched_count=0)
    assert payload["confidence"] == 0.95
    assert payload["low_confidence"] is False
    assert payload["needs_review"] is False
    assert payload["confidence_scale"] == "unit"


def test_ocr_s6_03_low_confidence_needs_review():
    unit = normalize_confidence(20)
    assert unit == 0.20
    assert is_low_confidence(unit) is True
    payload = build_ocr_confidence_payload(20, available=True, unmatched_count=0)
    assert payload["low_confidence"] is True
    assert payload["needs_review"] is True


def test_ocr_s6_04_boundary_threshold():
    # Strictly below → review; equal and above → OK
    assert is_low_confidence(0.59) is True
    assert is_low_confidence(0.60) is False
    assert is_low_confidence(0.61) is False
    below = build_ocr_confidence_payload(59, available=True)
    equal = build_ocr_confidence_payload(60, available=True)
    above = build_ocr_confidence_payload(61, available=True)
    assert below["needs_review"] is True
    assert equal["needs_review"] is False
    assert above["needs_review"] is False


def test_ocr_s6_05_invalid_confidence_requires_review():
    for raw in (None, "abc", float("nan"), -1, {}):
        assert normalize_confidence(raw) is None
        assert is_low_confidence(normalize_confidence(raw)) is True
        payload = build_ocr_confidence_payload(raw, available=True)
        assert payload["confidence"] is None
        assert payload["low_confidence"] is True
        assert payload["needs_review"] is True


# ─── Pipeline / API ──────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_ocr_s6_pipeline_normalizes_provider_score():
    db = AsyncMock()
    pipeline = PrescriptionOcrPipeline(db)

    async def fake_extract(_path):
        return OcrResult(
            text="Panadol 500 mg BD\n",
            confidence=95.0,
            provider="tesseract",
        )

    with patch.object(pipeline.ocr, "extract", side_effect=fake_extract), patch.object(
        pipeline.search,
        "search",
        AsyncMock(
            return_value={
                "results": [
                    {
                        "id": 1,
                        "name": "Panadol",
                        "generic_name": "paracetamol",
                        "strength": "500 mg",
                        "dosage_form": "tablet",
                        "artg_number": "A1",
                        "pbs_code": None,
                    }
                ]
            }
        ),
    ):
        result = await pipeline.process_file(Path("synth.png"), original_filename="synth.png")

    assert result["ocr"]["confidence"] == 0.95
    assert result["ocr"]["confidence_scale"] == "unit"
    assert result["ocr"]["low_confidence"] is False
    assert result["summary"]["ocr_available"] is True
    assert result["medicines"]
    assert result["medicines"][0]["match_status"] == "MATCHED"
    assert result["medicines"][0]["confirmed_medicine"] is False


@pytest.mark.anyio
async def test_ocr_s6_08_unavailable_safe():
    db = AsyncMock()
    pipeline = PrescriptionOcrPipeline(db)

    async def fake_extract(_path):
        return OcrResult(
            text="[OCR not available - tesseract binary not in PATH]",
            confidence=None,
            provider="tesseract",
            warnings=["tesseract not in PATH"],
        )

    with patch.object(pipeline.ocr, "extract", side_effect=fake_extract):
        result = await pipeline.process_file(Path("x.png"), original_filename="x.png")

    assert result["summary"]["ocr_available"] is False
    assert result["ocr"]["available"] is False
    assert result["ocr"]["text"] == ""
    assert result["ocr"]["confidence"] is None
    assert result["ocr"]["needs_review"] is True
    assert result["medicines"] == []


@pytest.mark.anyio
async def test_ocr_s6_09_catalogue_match_regression():
    """OCR-extracted fields remain unconfirmed; candidates are catalog."""
    db = AsyncMock()
    pipeline = PrescriptionOcrPipeline(db)

    async def fake_extract(_path):
        return OcrResult(text="Amoxil 500 mg TDS\n", confidence=90.0, provider="fixture")

    with patch.object(pipeline.ocr, "extract", side_effect=fake_extract), patch.object(
        pipeline.search,
        "search",
        AsyncMock(
            return_value={
                "results": [
                    {
                        "id": 42,
                        "name": "Amoxil",
                        "generic_name": "amoxicillin",
                        "strength": "500 mg",
                        "dosage_form": "capsule",
                        "artg_number": "ARTG1",
                        "pbs_code": "PBS1",
                    }
                ]
            }
        ),
    ):
        result = await pipeline.process_file(Path("a.png"), original_filename="a.png")

    med = result["medicines"][0]
    assert med["source"] == "ocr_extracted"
    assert med["confirmed_medicine"] is False
    assert med["candidates"][0]["medicine_id"] == 42
    assert med["candidates"][0]["confirmed_medicine"] is True
    assert med["candidates"][0]["source"] == "database"


def test_ocr_s6_10_legacy_persist_disabled():
    sig = inspect.signature(rx.scan_prescription)
    default = getattr(sig.parameters["persist"].default, "default", sig.parameters["persist"].default)
    assert default is False
    src = Path(rx.__file__).read_text(encoding="utf-8")
    assert "Legacy persist=true auto-save is disabled" in src
    assert "analyze_prescription" not in src


@pytest.mark.anyio
async def test_ocr_s6_06_07_confirm_requires_medicines_and_auth():
    """Confirm path still requires auth + medicines; does not auto-OCR-save."""
    owner = _user(1)
    app = FastAPI()
    app.include_router(rx.router, prefix="/api/v1/prescriptions")

    async def _u():
        return owner

    async def _db():
        yield AsyncMock()

    app.dependency_overrides[get_current_user] = _u
    app.dependency_overrides[get_db] = _db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Missing medicines → 400 (cannot silent-save empty/uncertain payload)
        resp = await client.post(
            "/api/v1/prescriptions/confirm",
            data={"medicines_json": "[]"},
            files={"file": ("x.pdf", b"%PDF-1.4 synth", "application/pdf")},
        )
    assert resp.status_code == 400


@pytest.mark.anyio
async def test_ocr_s6_10_persist_true_rejected():
    owner = _user(1)
    app = FastAPI()
    app.include_router(rx.router, prefix="/api/v1/prescriptions")

    async def _u():
        return owner

    async def _db():
        yield AsyncMock()

    app.dependency_overrides[get_current_user] = _u
    app.dependency_overrides[get_db] = _db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/prescriptions/scan",
            data={"persist": "true"},
            files={"file": ("x.pdf", b"%PDF-1.4 synth", "application/pdf")},
        )
    assert resp.status_code == 400
    assert "disabled" in resp.json()["detail"].lower()
    assert "legacy_persisted" not in resp.json()


@pytest.mark.anyio
async def test_ocr_s6_11_wrong_user_get_denied():
    other = _user(2)
    app = FastAPI()
    app.include_router(rx.router, prefix="/api/v1/prescriptions")

    async def _u():
        return other

    db = AsyncMock()
    result = MagicMock()
    result.scalar_one_or_none.return_value = None
    db.execute = AsyncMock(return_value=result)

    async def _db():
        yield db

    app.dependency_overrides[get_current_user] = _u
    app.dependency_overrides[get_db] = _db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/prescriptions/99")
    assert resp.status_code == 404


def test_ocr_s6_12_safe_logging_no_payload_in_confidence_module():
    src = Path(conf_mod.__file__).read_text(encoding="utf-8")
    pipeline_src = Path(
        __import__("app.services.prescription_ocr_pipeline", fromlist=["x"]).__file__
    ).read_text(encoding="utf-8")
    assert "logger.info(ocr.text" not in pipeline_src
    assert "print(" not in src
    # Confidence module is pure — no logging of document contents
    assert "ocr.text" not in src


def test_ocr_s6_threshold_constant_documented():
    assert OCR_REVIEW_THRESHOLD == 0.60
