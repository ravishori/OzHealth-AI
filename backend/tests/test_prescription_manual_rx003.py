"""HN-RX-003 — manual prescription entry API contracts."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.api.routes import prescriptions as rx_route
from app.core.deps import get_current_user
from app.core.database import get_db
from app.schemas.prescription import ManualPrescriptionCreate, ManualMedicineEntry


def _user(uid: int = 1, allergies=None):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@ex.com",
        is_active=True,
        token_version=0,
        allergies=allergies,
    )


def _catalog_med(
    mid: int,
    name: str,
    *,
    generic: str | None = None,
    brand: str | None = None,
    artg: str | None = None,
    normalized: str | None = None,
):
    return SimpleNamespace(
        id=mid,
        name=name,
        generic_name=generic,
        brand_name=brand,
        normalized_name=normalized,
        tga_artg_number=artg,
    )


def _rx_app(user=None):
    app = FastAPI()
    app.include_router(rx_route.router, prefix="/api/v1/prescriptions")

    async def _override_db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = _override_db
    if user is not None:
        async def _override_user():
            return user

        app.dependency_overrides[get_current_user] = _override_user
    return app


def _capture_db(prescription_id: int = 77):
    """AsyncSession mock that assigns id on refresh and records added objects."""
    db = AsyncMock()
    added: list = []

    def _add(obj):
        added.append(obj)

    async def _refresh(obj):
        if getattr(obj, "id", None) is None:
            obj.id = prescription_id
        if getattr(obj, "created_at", None) is None:
            obj.created_at = datetime.now(timezone.utc)

    db.add = MagicMock(side_effect=_add)
    db.commit = AsyncMock()
    db.refresh = AsyncMock(side_effect=_refresh)
    db.flush = AsyncMock()
    db._added = added
    return db


# ── RX-MANUAL-01 / 04 / 05 / 06 ───────────────────────────────────────────────


@pytest.mark.anyio
async def test_rx_manual_01_04_05_06_create_persists_distinguishable():
    """Authenticated create; persists; distinguishable from OCR; doctor_name optional."""
    user = _user(1)
    app = _rx_app(user)
    db = _capture_db(77)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    payload = {
        "medicines": [
            {
                "name": "Panadol",
                "dosage": "500mg",
                "frequency": "twice daily",
                "catalog_medicine_id": 10,
                "match_status": "MATCHED",
            }
        ],
        "doctor_name": "Dr Smith",
    }

    with patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(return_value={"safe": True, "duplicates": []})
    ), patch.object(
        rx_route, "_allergy_alerts_for_user", new=AsyncMock(return_value=None)
    ), patch.object(
        rx_route,
        "_validate_manual_catalogue_medicine",
        new=AsyncMock(return_value=_catalog_med(10, "Panadol", artg="12345")),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post("/api/v1/prescriptions/manual", json=payload)

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["id"] == 77
    assert body["entry_mode"] == "manual"
    assert body["doctor_name"] == "Dr Smith"
    assert body["medical_record_id"] is None
    assert body["medicines"][0]["name"] == "Panadol"
    assert body["medicines"][0]["entry_mode"] == "manual"
    assert body["medicines"][0]["source"] == "manual"
    assert body["medicines"][0]["catalog_medicine_id"] == 10
    assert body["medicines"][0]["match_status"] == "MATCHED"
    assert body["medicines"][0]["artg_number"] == "12345"

    assert len(db._added) == 1
    saved = db._added[0]
    assert saved.raw_ocr_text is None
    assert saved.user_id == 1
    meds = json.loads(saved.extracted_medicines)
    assert meds[0]["entry_mode"] == "manual"
    assert "Manual prescription entry" in (saved.ai_summary or "")


@pytest.mark.anyio
async def test_rx_manual_06b_doctor_name_optional_omitted():
    user = _user(1)
    app = _rx_app(user)
    db = _capture_db(78)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(return_value={"safe": True, "duplicates": []})
    ), patch.object(
        rx_route, "_allergy_alerts_for_user", new=AsyncMock(return_value=None)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={"medicines": [{"name": "Ibuprofen"}]},
            )
    assert resp.status_code == 200
    assert resp.json()["doctor_name"] is None


# ── RX-MANUAL-02 ──────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rx_manual_02_unauthenticated_rejected():
    app = _rx_app(user=None)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/prescriptions/manual",
            json={"medicines": [{"name": "Panadol"}]},
        )
    assert resp.status_code in (401, 403, 422)


# ── RX-MANUAL-03 ──────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rx_manual_03_empty_medicines_rejected():
    user = _user(1)
    app = _rx_app(user)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp_empty = await client.post(
            "/api/v1/prescriptions/manual",
            json={"medicines": []},
        )
        resp_blank = await client.post(
            "/api/v1/prescriptions/manual",
            json={"medicines": [{"name": "   "}]},
        )
    assert resp_empty.status_code == 422
    assert resp_blank.status_code == 422


# ── RX-MANUAL-07 / 08 ─────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rx_manual_07_owner_can_retrieve():
    user = _user(1)
    app = _rx_app(user)
    prescription = SimpleNamespace(
        id=42,
        user_id=1,
        family_member_id=None,
        medical_record_id=None,
        doctor_name="Dr A",
        hospital=None,
        prescription_date=None,
        raw_ocr_text=None,
        extracted_medicines=json.dumps(
            [{"name": "Panadol", "source": "manual", "entry_mode": "manual"}]
        ),
        ai_summary=rx_route._MANUAL_SUMMARY,
        created_at=datetime.now(timezone.utc),
    )

    async def _override_db():
        db = AsyncMock()
        result = MagicMock()
        result.scalar_one_or_none.return_value = prescription
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(
        rx_route,
        "catalogue_duplicate_warnings",
        new=AsyncMock(return_value={"safe": True, "duplicates": [], "available": False}),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/prescriptions/42")
    assert resp.status_code == 200
    body = resp.json()
    assert body["entry_mode"] == "manual"
    assert body["medicines"][0]["name"] == "Panadol"


@pytest.mark.anyio
async def test_rx_manual_08_other_user_cannot_retrieve():
    user = _user(2)
    app = _rx_app(user)

    async def _override_db():
        db = AsyncMock()
        result = MagicMock()
        # Ownership filter returns none for other user
        result.scalar_one_or_none.return_value = None
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_db] = _override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/prescriptions/42")
    assert resp.status_code == 404


# ── RX-MANUAL-09 / 10 ─────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rx_manual_09_owned_active_family_member():
    user = _user(1)
    app = _rx_app(user)
    db = _capture_db(90)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(
        rx_route,
        "_require_owned_active_family_member",
        new=AsyncMock(return_value=SimpleNamespace(id=5, name="Alex")),
    ) as req, patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(return_value={"safe": True, "duplicates": []})
    ), patch.object(
        rx_route, "_allergy_alerts_for_user", new=AsyncMock(return_value=None)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={
                    "medicines": [{"name": "Metformin"}],
                    "family_member_id": 5,
                },
            )
    assert resp.status_code == 200
    assert resp.json()["family_member_id"] == 5
    req.assert_awaited()


@pytest.mark.anyio
async def test_rx_manual_10_unowned_or_inactive_family_rejected():
    user = _user(1)
    app = _rx_app(user)

    async def _override_db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = _override_db

    with patch.object(
        rx_route,
        "_require_owned_active_family_member",
        new=AsyncMock(side_effect=HTTPException(status_code=404, detail="Family member not found")),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={
                    "medicines": [{"name": "Metformin"}],
                    "family_member_id": 999,
                },
            )
    assert resp.status_code == 404


@pytest.mark.anyio
async def test_rx_manual_10b_require_helper_filters_owner_and_active():
    db = AsyncMock()
    result = MagicMock()
    result.scalar_one_or_none.return_value = None
    db.execute = AsyncMock(return_value=result)
    with pytest.raises(HTTPException) as exc:
        await rx_route._require_owned_active_family_member(db, 1, 99)
    assert exc.value.status_code == 404


# ── RX-MANUAL-11 / 12 ─────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_rx_manual_11_allergy_checks_invoked():
    user = _user(1, allergies=json.dumps(["penicillin"]))
    app = _rx_app(user)
    db = _capture_db(91)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db
    allergy = {"safe": False, "conflicts": [{"medicine": "Amoxicillin"}]}

    with patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(return_value={"safe": True, "duplicates": []})
    ), patch(
        "app.api.routes.prescriptions.check_allergy_conflicts",
        new=AsyncMock(return_value=allergy),
    ) as allergy_fn:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={"medicines": [{"name": "Amoxicillin"}]},
            )
    assert resp.status_code == 200
    assert resp.json()["allergy_alerts"] == allergy
    allergy_fn.assert_awaited()


@pytest.mark.anyio
async def test_rx_manual_12_med007_catalogue_duplicate_semantics():
    """Manual path uses catalogue_duplicate_warnings — not generic/ingredient."""
    user = _user(1)
    app = _rx_app(user)
    db = _capture_db(92)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db
    dup = {
        "safe": False,
        "duplicates": [
            {
                "medicine_a": "Panadol",
                "medicine_b": "Paracetamol",
                "reason": "same canonical_key (para-500)",
                "source": "database",
            }
        ],
        "source": "database",
        "available": True,
        "note": rx_route._DUP_NOTE,
    }

    async def _validate(db, catalog_medicine_id, submitted_name):
        if catalog_medicine_id == 10:
            return _catalog_med(10, "Panadol")
        if catalog_medicine_id == 11:
            return _catalog_med(11, "Paracetamol", generic="Paracetamol")
        raise HTTPException(status_code=400, detail="Catalogue medicine not found")

    with patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(return_value=dup)
    ) as dup_fn, patch.object(
        rx_route, "_allergy_alerts_for_user", new=AsyncMock(return_value=None)
    ), patch.object(
        rx_route, "_validate_manual_catalogue_medicine", new=AsyncMock(side_effect=_validate)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={
                    "medicines": [
                        {"name": "Panadol", "catalog_medicine_id": 10},
                        {"name": "Paracetamol", "catalog_medicine_id": 11},
                    ]
                },
            )
    assert resp.status_code == 200
    body = resp.json()
    assert body["duplicate_warnings"]["safe"] is False
    assert body["duplicate_warnings"]["source"] == "database"
    # Ensure helper received catalogue ids path (MED-007), not reinvented detector
    dup_fn.assert_awaited()
    args = dup_fn.await_args.args
    assert len(args[1]) == 2
    assert args[1][0]["catalog_medicine_id"] == 10
    assert args[1][0]["match_status"] == "MATCHED"
    assert args[1][1]["catalog_medicine_id"] == 11


def test_rx_manual_sanitize_does_not_invent_catalogue_id():
    out = rx_route._sanitize_manual_medicines(
        [ManualMedicineEntry(name="Mystery Pill", dosage="1 tab")]
    )
    assert out[0]["catalog_medicine_id"] is None
    assert out[0]["match_status"] == "UNMATCHED"
    assert out[0]["entry_mode"] == "manual"


def test_rx_manual_sanitize_strips_client_matched_claim():
    """Client MATCHED / catalogue id are not authoritative in sync scrubber."""
    out = rx_route._sanitize_manual_medicines(
        [
            {
                "name": "Bogus",
                "catalog_medicine_id": 999999999,
                "match_status": "MATCHED",
                "artg_number": "FAKE-ARTG",
            }
        ]
    )
    assert out[0]["catalog_medicine_id"] is None
    assert out[0]["match_status"] == "UNMATCHED"
    assert out[0]["artg_number"] is None


def test_rx_manual_infer_entry_mode_distinguishable():
    assert (
        rx_route._infer_entry_mode(
            [{"name": "A", "entry_mode": "manual", "source": "manual"}], None
        )
        == "manual"
    )
    assert (
        rx_route._infer_entry_mode(
            [{"name": "A", "source": "user_confirmed", "entry_mode": "ocr"}],
            "raw text",
        )
        == "ocr"
    )


def test_rx_manual_schema_rejects_empty_list():
    with pytest.raises(Exception):
        ManualPrescriptionCreate(medicines=[])


def test_rx_manual_catalogue_name_compatibility():
    panadol = _catalog_med(1, "Panadol 500mg", generic="Paracetamol")
    warfarin = _catalog_med(2, "Warfarin", generic="Warfarin")
    assert rx_route._manual_catalogue_name_compatible("Panadol", panadol) is True
    assert rx_route._manual_catalogue_name_compatible("paracetamol", panadol) is True
    assert rx_route._manual_catalogue_name_compatible("Amoxicillin", warfarin) is False


# ── RX-MANUAL-CAT-01..08 — catalogue identity integrity ───────────────────────


@pytest.mark.anyio
async def test_rx_manual_cat_01_valid_id_after_authoritative_lookup():
    """RX-MANUAL-CAT-01"""
    user = _user(1)
    app = _rx_app(user)
    db = _capture_db(201)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db
    med = _catalog_med(10, "Panadol", generic="Paracetamol", artg="ARTG-10")

    with patch.object(
        rx_route, "_validate_manual_catalogue_medicine", new=AsyncMock(return_value=med)
    ) as val, patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(return_value={"safe": True, "duplicates": []})
    ), patch.object(
        rx_route, "_allergy_alerts_for_user", new=AsyncMock(return_value=None)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={"medicines": [{"name": "Panadol", "catalog_medicine_id": 10}]},
            )
    assert resp.status_code == 200
    body = resp.json()["medicines"][0]
    assert body["catalog_medicine_id"] == 10
    assert body["match_status"] == "MATCHED"
    assert body["artg_number"] == "ARTG-10"
    val.assert_awaited()


@pytest.mark.anyio
async def test_rx_manual_cat_02_nonexistent_id_rejected():
    """RX-MANUAL-CAT-02"""
    user = _user(1)
    app = _rx_app(user)

    async def _override_db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = _override_db

    with patch.object(
        rx_route,
        "_validate_manual_catalogue_medicine",
        new=AsyncMock(
            side_effect=HTTPException(
                status_code=400,
                detail="Catalogue medicine not found for the supplied id.",
            )
        ),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={
                    "medicines": [
                        {"name": "Fake", "catalog_medicine_id": 999999999}
                    ]
                },
            )
    assert resp.status_code == 400
    assert "not found" in resp.json()["detail"].lower()


@pytest.mark.anyio
async def test_rx_manual_cat_03_arbitrary_id_cannot_become_matched():
    """RX-MANUAL-CAT-03 — end-to-end validate rejects missing Medicine row."""
    user = _user(1)
    app = _rx_app(user)

    async def _override_db():
        db = AsyncMock()
        result = MagicMock()
        result.scalar_one_or_none.return_value = None
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_db] = _override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/prescriptions/manual",
            json={
                "medicines": [
                    {
                        "name": "Anything",
                        "catalog_medicine_id": 888888,
                        "match_status": "MATCHED",
                    }
                ]
            },
        )
    assert resp.status_code == 400
    assert resp.json().get("medicines") is None or "medicines" not in resp.json()


@pytest.mark.anyio
async def test_rx_manual_cat_04_wrong_existing_id_rejected():
    """RX-MANUAL-CAT-04 — Amoxicillin + Warfarin catalogue id must not MATCH."""
    user = _user(1)
    app = _rx_app(user)

    async def _override_db():
        db = AsyncMock()
        result = MagicMock()
        result.scalar_one_or_none.return_value = _catalog_med(
            55, "Warfarin 5mg", generic="Warfarin"
        )
        db.execute = AsyncMock(return_value=result)
        yield db

    app.dependency_overrides[get_db] = _override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/prescriptions/manual",
            json={
                "medicines": [
                    {"name": "Amoxicillin", "catalog_medicine_id": 55}
                ]
            },
        )
    assert resp.status_code == 400
    assert "does not match" in resp.json()["detail"].lower()


@pytest.mark.anyio
async def test_rx_manual_cat_05_name_only_unmatched():
    """RX-MANUAL-CAT-05"""
    user = _user(1)
    app = _rx_app(user)
    db = _capture_db(205)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(return_value={"safe": True, "duplicates": []})
    ), patch.object(
        rx_route, "_allergy_alerts_for_user", new=AsyncMock(return_value=None)
    ), patch.object(
        rx_route, "_validate_manual_catalogue_medicine"
    ) as val:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={"medicines": [{"name": "Mystery Compound"}]},
            )
    assert resp.status_code == 200
    med = resp.json()["medicines"][0]
    assert med["catalog_medicine_id"] is None
    assert med["match_status"] == "UNMATCHED"
    assert med["artg_number"] is None
    val.assert_not_awaited()


@pytest.mark.anyio
async def test_rx_manual_cat_06_client_match_status_cannot_force_matched():
    """RX-MANUAL-CAT-06 — without catalogue id, MATCHED claim is ignored."""
    user = _user(1)
    app = _rx_app(user)
    db = _capture_db(206)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    with patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(return_value={"safe": True, "duplicates": []})
    ), patch.object(
        rx_route, "_allergy_alerts_for_user", new=AsyncMock(return_value=None)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={
                    "medicines": [
                        {
                            "name": "Ibuprofen",
                            "match_status": "MATCHED",
                            "artg_number": "CLIENT-ARTG",
                        }
                    ]
                },
            )
    assert resp.status_code == 200
    med = resp.json()["medicines"][0]
    assert med["match_status"] == "UNMATCHED"
    assert med["catalog_medicine_id"] is None
    assert med["artg_number"] is None


@pytest.mark.anyio
async def test_rx_manual_cat_07_client_artg_cannot_fabricate_metadata():
    """RX-MANUAL-CAT-07 — ARTG comes from catalogue only after validation."""
    user = _user(1)
    app = _rx_app(user)
    db = _capture_db(207)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db
    med = _catalog_med(10, "Panadol", artg="SERVER-ARTG")

    with patch.object(
        rx_route, "_validate_manual_catalogue_medicine", new=AsyncMock(return_value=med)
    ), patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(return_value={"safe": True, "duplicates": []})
    ), patch.object(
        rx_route, "_allergy_alerts_for_user", new=AsyncMock(return_value=None)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={
                    "medicines": [
                        {
                            "name": "Panadol",
                            "catalog_medicine_id": 10,
                            "artg_number": "CLIENT-FAKE-ARTG",
                        }
                    ]
                },
            )
    assert resp.status_code == 200
    assert resp.json()["medicines"][0]["artg_number"] == "SERVER-ARTG"


@pytest.mark.anyio
async def test_rx_manual_cat_08_med007_receives_trustworthy_identity():
    """RX-MANUAL-CAT-08"""
    user = _user(1)
    app = _rx_app(user)
    db = _capture_db(208)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db

    async def _validate(db, catalog_medicine_id, submitted_name):
        return _catalog_med(catalog_medicine_id, submitted_name)

    captured = {}

    async def _dup(db, medicines):
        captured["medicines"] = medicines
        return {"safe": True, "duplicates": [], "source": "database", "available": True}

    with patch.object(
        rx_route, "_validate_manual_catalogue_medicine", new=AsyncMock(side_effect=_validate)
    ), patch.object(
        rx_route, "catalogue_duplicate_warnings", new=AsyncMock(side_effect=_dup)
    ), patch.object(
        rx_route, "_allergy_alerts_for_user", new=AsyncMock(return_value=None)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/prescriptions/manual",
                json={
                    "medicines": [
                        {"name": "Panadol", "catalog_medicine_id": 10},
                        {"name": "Panadol Extra", "catalog_medicine_id": 10},
                    ]
                },
            )
    assert resp.status_code == 200
    meds = captured["medicines"]
    assert all(m["match_status"] == "MATCHED" for m in meds)
    assert all(m["catalog_medicine_id"] == 10 for m in meds)
    assert all(m.get("source") == "manual" for m in meds)