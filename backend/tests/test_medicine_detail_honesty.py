"""HN-MED-008 — medicine detail honesty / AI vs DB provenance (MED-HONEST-*)."""

from __future__ import annotations

import inspect
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api.routes import medicines as medicines_route
from app.services import ai_prompt_safety as safety
from app.services import ai_service
from app.services.medicine_explanation_service import MedicineExplanationService


def _med(**kwargs):
    defaults = dict(
        id=42,
        name="Amoxicillin 500 mg Capsule",
        generic_name="Amoxicillin",
        composition="Amoxicillin 500 mg",
        drug_class="Penicillin antibiotic",
        therapeutic_class=None,
        uses="Bacterial infections",
        consumer_information=None,
        standard_dosage=None,
        side_effects=None,
        interactions=None,
        contraindications=None,
        warnings=None,
        storage_instructions=None,
        tga_registered=True,
        tga_artg_number="AUST R 12345",
        schedule="S4",
        manufacturer="TestPharm",
        sponsor=None,
        pregnancy_category=None,
        primary_source="TGA",
        pbs_code=None,
    )
    defaults.update(kwargs)
    return SimpleNamespace(**defaults)


# ── MED-HONEST-01 / 02 / 05 / 06 / 07 / 08 — _to_dict provenance ─────────────


def test_med_honest_01_known_medicine_database_facts():
    """MED-HONEST-01 — DB fields returned with database provenance; AI not required."""
    m = _med(composition="Amoxicillin 500 mg", standard_dosage=None)
    out = medicines_route._to_dict(m)
    assert out["composition"] == "Amoxicillin 500 mg"
    assert out["field_sources"]["composition"] == "database"
    assert out["provenance"]["structured_clinical"] == "database_only"
    assert out["provenance"]["ai_may_complete_structured_fields"] is False
    assert out["provenance"]["labels"]["database"] == "From medicine database"
    assert "standard_dosage" not in (out.get("ai") or {})


def test_med_honest_02_missing_clinical_remain_unavailable():
    """MED-HONEST-02 — missing dosage/side effects stay unavailable."""
    m = _med(standard_dosage=None, side_effects=None, interactions="")
    out = medicines_route._to_dict(m)
    assert out["standard_dosage"] in (None, "")
    assert out["side_effects"] in (None, "")
    assert out["field_sources"]["standard_dosage"] == "unavailable"
    assert out["field_sources"]["side_effects"] == "unavailable"
    assert out["field_sources"]["interactions"] == "unavailable"
    assert out["provenance"]["labels"]["unavailable"] == "Information not available"


def test_med_honest_05_unsupported_dosage_not_ai_filled_in_dict():
    """MED-HONEST-05 — _to_dict never invents dosage."""
    m = _med(standard_dosage=None)
    out = medicines_route._to_dict(m)
    assert out["standard_dosage"] is None
    assert out["field_sources"]["standard_dosage"] == "unavailable"


def test_med_honest_06_unsupported_interactions_not_ai_filled():
    """MED-HONEST-06"""
    m = _med(interactions=None)
    out = medicines_route._to_dict(m)
    assert out["interactions"] is None
    assert out["field_sources"]["interactions"] == "unavailable"


def test_med_honest_07_tga_pbs_from_database_only():
    """MED-HONEST-07 — regulatory flags come from catalogue columns."""
    m = _med(tga_registered=False, tga_artg_number=None, pbs_code=None)
    out = medicines_route._to_dict(m)
    assert out["tga_registered"] is False
    assert out["field_sources"]["tga_registered"] == "database"
    assert out["field_sources"]["pbs_code"] == "unavailable"
    assert out["field_sources"]["tga_artg_number"] == "unavailable"
    note = out["provenance"]["note"].lower()
    assert "cmi" in note or "tga" in note


def test_med_honest_08_provenance_distinguishes_three_states():
    """MED-HONEST-08"""
    out = medicines_route._to_dict(_med())
    labels = out["provenance"]["labels"]
    assert labels["database"]
    assert labels["unavailable"]
    assert labels["ai_explanation"]
    assert labels["database"] != labels["ai_explanation"]
    assert labels["unavailable"] != labels["database"]


# ── MED-HONEST-03 / 04 — unknown / ambiguous via /ai-info ────────────────────


@pytest.mark.asyncio
async def test_med_honest_03_unknown_medicine_ai_info_no_fabricated_record():
    """MED-HONEST-03 — XYZ-DOES-NOT-EXIST → 404, no invented clinical map."""
    empty_result = MagicMock()
    empty_result.scalars.return_value.all.return_value = []
    db = AsyncMock()
    db.execute = AsyncMock(return_value=empty_result)
    user = SimpleNamespace(id=1)

    with patch.object(
        ai_service, "get_medicine_info_from_ai", new_callable=AsyncMock
    ) as mocked_ai:
        with pytest.raises(HTTPException) as ei:
            await medicines_route.get_ai_medicine_info(
                "XYZ-DOES-NOT-EXIST", db=db, current_user=user
            )
        assert ei.value.status_code == 404
        mocked_ai.assert_not_called()
        detail = str(ei.value.detail).lower()
        assert "catalogue" in detail or "catalog" in detail


@pytest.mark.asyncio
async def test_med_honest_04_ambiguous_prefix_not_confirmed_via_ai_info():
    """MED-HONEST-04 — free-text 'amox' is not an exact catalogue name match."""
    empty_result = MagicMock()
    empty_result.scalars.return_value.all.return_value = []
    db = AsyncMock()
    db.execute = AsyncMock(return_value=empty_result)
    user = SimpleNamespace(id=1)

    with pytest.raises(HTTPException) as ei:
        await medicines_route.get_ai_medicine_info(
            "amox", db=db, current_user=user
        )
    assert ei.value.status_code == 404


@pytest.mark.asyncio
async def test_med_honest_03b_ai_info_matched_returns_explanation_not_flat_clinical():
    """Matched name returns explanation envelope; never freeform Haiku clinical JSON."""
    med = _med(id=99, name="Paracetamol 500 mg Tablet")
    match_result = MagicMock()
    match_result.scalars.return_value.all.return_value = [med]
    db = AsyncMock()
    db.execute = AsyncMock(return_value=match_result)
    user = SimpleNamespace(id=1)

    fake_explanation = {
        "medicine_id": 99,
        "confirmed_medicine": True,
        "common_side_effects": {
            "text": None,
            "source": "unavailable",
            "available": False,
        },
        "ai": {
            "invented_clinical_facts": False,
            "role": "rephrase_database_fields_only",
        },
        "tga_pbs": {"source": "database", "tga_registered": True},
    }

    with patch.object(
        MedicineExplanationService,
        "explain",
        new_callable=AsyncMock,
        return_value=fake_explanation,
    ):
        with patch.object(
            ai_service, "get_medicine_info_from_ai", new_callable=AsyncMock
        ) as mocked_ai:
            out = await medicines_route.get_ai_medicine_info(
                "Paracetamol 500 mg Tablet", db=db, current_user=user
            )
            mocked_ai.assert_not_called()

    assert out["catalog_matched"] is True
    assert out["structured_clinical_from_ai"] is False
    assert out["confirmed_medicine"] is True
    assert "standard_dosage" not in out or out.get("standard_dosage") is None
    assert out["ai"]["invented_clinical_facts"] is False


# ── MED-HONEST-09 — AI safety not bypassed on medicine AI path ───────────────


def test_med_honest_09_medicine_ai_path_keeps_hn_ai_010_fencing():
    """MED-HONEST-09 — leftover get_medicine_info_from_ai still fences + safety."""
    src = inspect.getsource(ai_service.get_medicine_info_from_ai)
    assert "wrap_untrusted" in src
    assert "UNTRUSTED" in src
    route_src = inspect.getsource(medicines_route.get_ai_medicine_info)
    assert "get_medicine_info_from_ai" not in route_src
    assert "MedicineExplanationService" in route_src
    assert (
        "UNTRUSTED" in safety.SAFETY_POLICY_ADDENDUM
        or "untrusted" in safety.SAFETY_POLICY_ADDENDUM.lower()
    )


# ── MED-HONEST-10 — no sensitive payload logging ─────────────────────────────


def test_med_honest_10_no_raw_ai_medical_payload_logging():
    """MED-HONEST-10 — HN-SEC-007 logging hygiene on medicine AI helpers."""
    src = inspect.getsource(ai_service.get_medicine_info_from_ai)
    for bad in ("json.dumps", "logger.info(info", "print(info", "ai_log.info(text"):
        assert bad not in src
    route_src = inspect.getsource(medicines_route.get_ai_medicine_info)
    assert "logger" not in route_src or "payload" not in route_src.lower()
    to_dict_src = inspect.getsource(medicines_route._to_dict)
    assert "logger" not in to_dict_src


def test_med_honest_search_does_not_call_ai():
    """Ambiguous search remains catalogue-only (supports MED-HONEST-04)."""
    src = inspect.getsource(medicines_route.search_medicines)
    assert "get_medicine_info_from_ai" not in src
    assert "CatalogMedicineSearchService" in src
