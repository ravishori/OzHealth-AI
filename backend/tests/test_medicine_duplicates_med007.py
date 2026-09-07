"""HN-MED-007 — Duplicate medicine detection (catalogue-grounded)."""
from __future__ import annotations

import json
import os
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import prescriptions as rx_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.services.medicine_safety_service import MedBundle, MedicineSafetyChecker


def _user(uid: int = 1):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@ex.com",
        is_active=True,
        token_version=0,
        allergies=None,
    )


def _bundle(
    mid: int,
    name: str,
    *,
    canonical_key: str | None = None,
    generic_name: str | None = None,
    active_ingredient: str | None = None,
    ingredients: list[dict] | None = None,
):
    return MedBundle(
        id=mid,
        name=name,
        generic_name=generic_name,
        active_ingredient=active_ingredient,
        canonical_key=canonical_key,
        interactions_text=None,
        ingredients=ingredients or [],
    )


@pytest.fixture
def anyio_backend():
    return "asyncio"


# ── MED-DUP-BE-01 / 02 / 03 / 04 — MedicineSafetyChecker._duplicates ─────────


def test_med_dup_be_01_distinct_medicines_not_duplicates():
    """MED-DUP-BE-01 — distinct catalogue identities are not duplicates."""
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(1, "Amoxicillin 500 mg", canonical_key="amox-500-cap")
    b = _bundle(2, "Ibuprofen 200 mg", canonical_key="ibu-200-tab")
    assert checker._duplicates([a, b]) == []


def test_med_dup_be_02_identical_canonical_key_detected():
    """MED-DUP-BE-02 — identical canonical_key is detected."""
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(10, "Panadol", canonical_key="paracetamol-500-tab")
    b = _bundle(11, "Paracetamol 500", canonical_key="paracetamol-500-tab")
    out = checker._duplicates([a, b])
    assert len(out) == 1
    assert out[0]["status"] == "DUPLICATE"
    assert out[0]["source"] == "database"
    assert "canonical_key" in out[0]["reason"]
    assert out[0]["medicine_a"]["name"] == "Panadol"
    assert out[0]["medicine_b"]["name"] == "Paracetamol 500"


def test_med_dup_be_02b_same_medicine_id_detected():
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(5, "Drug A", canonical_key="x")
    b = _bundle(5, "Drug A again", canonical_key="y")
    out = checker._duplicates([a, b])
    assert len(out) == 1
    assert "same medicine_id" in out[0]["reason"]


def test_med_dup_be_03_deterministic():
    """MED-DUP-BE-03 — same inputs always yield the same pairs."""
    checker = MedicineSafetyChecker(AsyncMock())
    meds = [
        _bundle(1, "A", canonical_key="k1"),
        _bundle(2, "B", canonical_key="k1"),
        _bundle(3, "C", canonical_key="k2"),
    ]
    first = checker._duplicates(meds)
    second = checker._duplicates(meds)
    assert first == second


def test_med_dup_be_04_null_optional_fields_do_not_crash():
    """MED-DUP-BE-04 — missing optional identity fields do not crash."""
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(1, "Only Name", canonical_key=None, generic_name=None)
    b = _bundle(2, "Other Name", canonical_key=None, generic_name=None)
    assert checker._duplicates([a, b]) == []


def test_med_dup_be_07_same_generic_different_strength_not_duplicate():
    """
    MED-DUP-BE-07 — same generic + different strength + different canonical
    identity => NOT DUPLICATE.

    Mirrors seed catalogue naming (Amoxicillin 500mg Capsules) vs a distinct
    strength product; identity is established only by medicine_id/canonical_key.
    """
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(
        1,
        "Amoxicillin 250 mg Capsule",
        canonical_key="amox-250-cap",
        generic_name="Amoxicillin",
        active_ingredient="Amoxicillin",
        ingredients=[{"name": "Amoxicillin"}],
    )
    b = _bundle(
        2,
        "Amoxicillin 500mg Capsules",
        canonical_key="amox-500-cap",
        generic_name="Amoxicillin",
        active_ingredient="Amoxicillin",
        ingredients=[{"name": "Amoxicillin"}],
    )
    assert checker._duplicates([a, b]) == []


def test_med_dup_be_08_same_generic_different_dosage_form_not_duplicate():
    """Same generic + different dosage form + different canonical => NOT DUPLICATE."""
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(
        1,
        "Amoxicillin 500 mg Capsule",
        canonical_key="amox-500-cap",
        generic_name="Amoxicillin",
        active_ingredient="Amoxicillin",
    )
    b = _bundle(
        2,
        "Amoxicillin 500 mg Suspension",
        canonical_key="amox-500-susp",
        generic_name="Amoxicillin",
        active_ingredient="Amoxicillin",
    )
    assert checker._duplicates([a, b]) == []


def test_med_dup_be_09_same_generic_different_route_not_duplicate():
    """
    Same generic + different route/canonical identity => NOT DUPLICATE.

    Medicine model has optional route; identity still comes from canonical_key,
    not from inventing a route-based formula.
    """
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(
        1,
        "Amoxicillin oral",
        canonical_key="amox-oral",
        generic_name="Amoxicillin",
    )
    b = _bundle(
        2,
        "Amoxicillin IV",
        canonical_key="amox-iv",
        generic_name="Amoxicillin",
    )
    assert checker._duplicates([a, b]) == []
    # Generic-name matching must not collapse differing catalogue identities.
    assert checker._duplicates(
        [
            _bundle(3, "X", canonical_key="k-a", generic_name="Amoxicillin"),
            _bundle(4, "Y", canonical_key="k-b", generic_name="Amoxicillin"),
        ]
    ) == []


def test_med_dup_be_10_shared_ingredient_different_identity_not_duplicate():
    """Shared ingredient + different canonical identity => NOT DUPLICATE."""
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(
        1,
        "Panadol",
        canonical_key="paracetamol-500-tab",
        generic_name="Paracetamol",
        active_ingredient="Paracetamol",
        ingredients=[{"name": "Paracetamol"}],
    )
    b = _bundle(
        2,
        "Panadol Osteo",
        canonical_key="paracetamol-665-mrr",
        generic_name="Paracetamol",
        active_ingredient="Paracetamol",
        ingredients=[{"name": "Paracetamol"}],
    )
    assert checker._duplicates([a, b]) == []


def test_med_dup_be_11_combination_product_shared_ingredient_not_duplicate():
    """Combination / related brand sharing an ingredient is not a catalogue duplicate."""
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(
        10,
        "Panadol",
        canonical_key="paracetamol-500-tab",
        generic_name="Paracetamol",
        active_ingredient="Paracetamol",
        ingredients=[{"name": "Paracetamol"}],
    )
    b = _bundle(
        12,
        "Panadol Cold & Flu",
        canonical_key="paracetamol-phenylephrine-combo",
        generic_name=None,
        active_ingredient="Paracetamol; Phenylephrine",
        ingredients=[
            {"name": "Paracetamol"},
            {"name": "Phenylephrine"},
        ],
    )
    assert checker._duplicates([a, b]) == []


def test_med_dup_be_12_null_canonical_keys_do_not_match_broadly():
    """Null/blank canonical_key pairs must not collapse via soft heuristics."""
    checker = MedicineSafetyChecker(AsyncMock())
    a = _bundle(
        1,
        "Amoxicillin 250",
        canonical_key=None,
        generic_name="Amoxicillin",
        active_ingredient="Amoxicillin",
        ingredients=[{"name": "Amoxicillin"}],
    )
    b = _bundle(
        2,
        "Amoxicillin 500",
        canonical_key="   ",
        generic_name="Amoxicillin",
        active_ingredient="Amoxicillin",
        ingredients=[{"name": "Amoxicillin"}],
    )
    assert checker._duplicates([a, b]) == []


# ── catalogue_duplicate_warnings helper ──────────────────────────────────────


@pytest.mark.anyio
async def test_med_dup_catalogue_helper_maps_pairs():
    db = AsyncMock()
    meds = [
        {"name": "Panadol", "catalog_medicine_id": 10},
        {"name": "Paracetamol", "catalog_medicine_id": 11},
    ]
    fake = {
        "duplicates": [
            {
                "medicine_a": {"medicine_id": 10, "name": "Panadol"},
                "medicine_b": {"medicine_id": 11, "name": "Paracetamol"},
                "reason": "same canonical_key (para-500)",
                "source": "database",
                "status": "DUPLICATE",
            }
        ]
    }
    with patch.object(
        MedicineSafetyChecker, "check", new=AsyncMock(return_value=fake)
    ):
        out = await rx_route.catalogue_duplicate_warnings(db, meds)
    assert out["safe"] is False
    assert out["source"] == "database"
    assert out["duplicates"][0]["medicine_a"] == "Panadol"
    assert out["duplicates"][0]["medicine_b"] == "Paracetamol"
    assert "canonical_key" in out["duplicates"][0]["risk"]
    assert "not a clinical diagnosis" in out["note"].lower() or "pharmacist" in out["note"].lower()
    assert "must not take" not in out["note"].lower()


@pytest.mark.anyio
async def test_med_dup_catalogue_helper_needs_two_ids():
    out = await rx_route.catalogue_duplicate_warnings(
        AsyncMock(), [{"name": "Only One", "catalog_medicine_id": 1}]
    )
    assert out["safe"] is True
    assert out["duplicates"] == []
    assert out["available"] is False


# ── MED-DUP-BE-05 / 06 — prescription GET wiring ─────────────────────────────


@pytest.mark.anyio
async def test_med_dup_be_05_unauthenticated_get_rejected():
    """MED-DUP-BE-05 — unauthenticated protected endpoint remains rejected."""
    app = FastAPI()
    app.include_router(rx_route.router, prefix="/api/v1/prescriptions")

    async def _db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = _db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/prescriptions/1")
    assert resp.status_code in (401, 403, 422)


@pytest.mark.anyio
async def test_med_dup_be_06_get_includes_catalogue_duplicate_warnings():
    """MED-DUP-BE-06 — GET detail returns duplicate_warnings; existing fields intact."""
    app = FastAPI()
    app.include_router(rx_route.router, prefix="/api/v1/prescriptions")
    user = _user(1)
    prescription = SimpleNamespace(
        id=42,
        user_id=1,
        family_member_id=None,
        medical_record_id=9,
        doctor_name="Dr Test",
        hospital="Clinic",
        prescription_date=None,
        extracted_medicines=json.dumps(
            [
                {"name": "Panadol", "catalog_medicine_id": 10},
                {"name": "Paracetamol", "catalog_medicine_id": 11},
            ]
        ),
        ai_summary="ok",
        created_at=None,
    )

    async def _override_user():
        return user

    async def _override_db():
        db = AsyncMock()
        result = MagicMock()
        result.scalar_one_or_none.return_value = prescription
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_current_user] = _override_user
    app.dependency_overrides[get_db] = _override_db

    fake = {
        "duplicates": [
            {
                "medicine_a": {"medicine_id": 10, "name": "Panadol"},
                "medicine_b": {"medicine_id": 11, "name": "Paracetamol"},
                "reason": "same canonical_key (para-500)",
                "source": "database",
                "status": "DUPLICATE",
            }
        ]
    }
    with patch.object(
        MedicineSafetyChecker, "check", new=AsyncMock(return_value=fake)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/prescriptions/42")
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == 42
    assert body["doctor_name"] == "Dr Test"
    assert isinstance(body["medicines"], list)
    assert body["duplicate_warnings"]["safe"] is False
    assert len(body["duplicate_warnings"]["duplicates"]) == 1
    assert body["duplicate_warnings"]["source"] == "database"


def test_med_dup_no_llm_import_on_confirm_path():
    """Confirm path must not use AI detect_duplicate_medicines as authority."""
    import inspect

    src = inspect.getsource(rx_route.confirm_prescription)
    assert "detect_duplicate_medicines" not in src
    assert "catalogue_duplicate_warnings" in src
    helper = inspect.getsource(rx_route.catalogue_duplicate_warnings)
    assert "MedicineSafetyChecker" in helper
    assert "detect_duplicate_medicines" not in helper
