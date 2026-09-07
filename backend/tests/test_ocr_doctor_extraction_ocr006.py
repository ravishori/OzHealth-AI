"""HN-OCR-006 — Deterministic doctor/prescriber extraction (non-LLM)."""
from __future__ import annotations

import inspect
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest

from app.services.ocr_provider import OcrResult
from app.services.prescription_doctor_extractor import extract_doctor_name
from app.services.prescription_medicine_extractor import extract_medicine_candidates
from app.services.prescription_ocr_pipeline import PrescriptionOcrPipeline


# ── BE-01..08 unit extraction ────────────────────────────────────────────────


def test_ocr006_be01_dr_dot_inline():
    """BE-01 — 'Dr. Jane Smith' extracts 'Jane Smith'."""
    assert extract_doctor_name("Dr. Jane Smith") == "Jane Smith"


def test_ocr006_be02_doctor_label_inline():
    """BE-02 — 'Doctor: Jane Smith' extracts 'Jane Smith'."""
    assert extract_doctor_name("Doctor: Jane Smith") == "Jane Smith"


def test_ocr006_be03_prescriber_label_inline():
    """BE-03 — 'Prescriber: Jane Smith' extracts 'Jane Smith'."""
    assert extract_doctor_name("Prescriber: Jane Smith") == "Jane Smith"


def test_ocr006_be04_label_plus_next_line():
    """BE-04 — label on one line + name on next line."""
    text = "Doctor:\nJane Smith\nPanadol 500 mg BD\n"
    assert extract_doctor_name(text) == "Jane Smith"
    text2 = "Dr:\nJane Smith\n"
    assert extract_doctor_name(text2) == "Jane Smith"


def test_ocr006_be05_doctor_line_not_medicine():
    """BE-05 — doctor-labelled line does not become a medicine."""
    text = "Dr. Jane Smith\nAmoxicillin 500 mg Capsule BD\n"
    meds = extract_medicine_candidates(text)
    names = [m.extracted_name.lower() for m in meds]
    assert all("jane" not in n and "smith" not in n for n in names)
    assert any("amoxicillin" in n for n in names)


def test_ocr006_be06_unlabelled_arbitrary_name_not_extracted():
    """BE-06 — unrelated person/name without doctor signal is NOT extracted."""
    text = "Patient: John Doe\nJane Smith\nPanadol 500 mg BD\n"
    assert extract_doctor_name(text) is None


def test_ocr006_be07_missing_doctor_signal():
    """BE-07 — blank/missing doctor signal returns None safely."""
    assert extract_doctor_name(None) is None
    assert extract_doctor_name("") is None
    assert extract_doctor_name("   ") is None
    assert extract_doctor_name("Panadol 500 mg BD\nIbuprofen 200 mg\n") is None


def test_ocr006_be08_whitespace_noise_conservative():
    """BE-08 — OCR whitespace/noise handled conservatively."""
    assert extract_doctor_name("  Doctor :   Jane   Smith  ") == "Jane Smith"
    assert extract_doctor_name("Prescribed by: Jane Smith") == "Jane Smith"
    assert extract_doctor_name("Medical Practitioner: Jane Smith") == "Jane Smith"
    assert extract_doctor_name("Treating Doctor: Jane Smith") == "Jane Smith"


def test_ocr006_be09_medicine_extraction_unchanged():
    """BE-09 — existing medicine extraction remains unchanged for pure med text."""
    text = "1. Amoxicillin 500 mg Capsule BD\n2. Ibuprofen 200 mg tablet TDS\n"
    meds = extract_medicine_candidates(text)
    assert len(meds) >= 2
    joined = " ".join(m.extracted_name.lower() for m in meds)
    assert "amoxicillin" in joined
    assert "ibuprofen" in joined
    assert extract_doctor_name(text) is None


def test_ocr006_be10_no_llm_in_extractor_or_pipeline():
    """BE-10 — doctor extraction does not use an LLM."""
    root = Path(__file__).resolve().parents[1]
    extractor_src = (root / "app/services/prescription_doctor_extractor.py").read_text(
        encoding="utf-8"
    )
    pipeline_src = inspect.getsource(PrescriptionOcrPipeline.process_file)
    for banned in (
        "anthropic",
        "openai",
        "claude",
        "analyze_prescription",
        "AsyncAnthropic",
        "ChatCompletion",
    ):
        assert banned.lower() not in extractor_src.lower()
        assert banned.lower() not in pipeline_src.lower()
    assert "extract_doctor_name" in pipeline_src


# ── Pipeline / API surface ───────────────────────────────────────────────────


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_ocr006_pipeline_includes_doctor_name():
    """Pipeline OCR response includes doctor_name when signal present."""
    db = AsyncMock()
    pipeline = PrescriptionOcrPipeline(db)

    async def fake_extract(_path):
        return OcrResult(
            text="Dr. Jane Smith\nPanadol 500 mg BD\n",
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
        out = await pipeline.process_file(Path("/tmp/fake.jpg"), original_filename="rx.jpg")

    assert out["doctor_name"] == "Jane Smith"
    assert "ocr" in out and "medicines" in out and "summary" in out
    assert out["ocr"]["available"] is True
    assert isinstance(out["medicines"], list)
    # Doctor must not appear as a medicine row
    for med in out["medicines"]:
        name = (med.get("extracted_name") or "").lower()
        assert "jane" not in name and "smith" not in name


@pytest.mark.anyio
async def test_ocr006_pipeline_doctor_none_without_signal():
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
        AsyncMock(return_value={"results": []}),
    ):
        out = await pipeline.process_file(Path("/tmp/fake.jpg"), original_filename="rx.jpg")

    assert out["doctor_name"] is None
    assert "medicines" in out
