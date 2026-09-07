from fastapi import APIRouter, Depends, HTTPException, Query
from app.core.log_decorator import LoggedAPIRoute
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func, select
from typing import Any, Optional

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.logging_config import audit_log
from app.models.user import User
from app.models.medicine import Medicine
from app.models.medicine_favourite import MedicineFavourite
from app.services.ai_service import get_medicine_alternatives, check_allergy_conflicts
from app.services.cache_service import CacheService, MEDICINE_DETAIL_TTL
from app.services.catalog_medicine_search_service import (
    CatalogMedicineSearchService,
    MAX_QUERY_LEN,
    clamp_limit,
)
from app.services.medicine_explanation_service import MedicineExplanationService
from app.services.medicine_safety_service import MedicineSafetyChecker

# HN-MED-008 — provenance labels (UI-facing; structured fields stay DB-only)
_PROVENANCE_LABELS = {
    "database": "From medicine database",
    "unavailable": "Information not available",
    "ai_explanation": "AI-generated explanation",
    "ai_rephrased_from_database": "AI-generated explanation",
}

router = APIRouter(route_class=LoggedAPIRoute)


class MedicineSafetyCheckRequest(BaseModel):
    medicine_ids: list[int] = Field(
        ...,
        min_length=1,
        max_length=30,
        description="Confirmed catalog medicine IDs (e.g. from OCR match)",
    )
    allergies: list[str] = Field(
        default_factory=list,
        description="Optional patient allergy strings (ingredient names)",
    )


@router.get("/search")
async def search_medicines(
    q: str = Query(
        ...,
        min_length=1,
        max_length=MAX_QUERY_LEN,
        description="Medicine name, generic, brand, ARTG, PBS code, or ingredient",
    ),
    limit: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Minimum AU medicine catalog search (MigrationTest).

    Exact / prefix / partial text over name, generic, brand, ARTG, PBS,
    ingredient, and canonical key. Uses existing PostgreSQL indexes only.
    Does not call AI, OCR, interactions, or chatbot paths.
    """
    try:
        service = CatalogMedicineSearchService(db)
        return await service.search(q, limit=clamp_limit(limit))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/safety-check")
async def medicine_safety_check(
    body: MedicineSafetyCheckRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Minimum medicine safety checker (database only — no LLM invention).

    Checks duplicates, allergy/ingredient conflicts, and interactions for
    confirmed catalog medicine_ids. UNKNOWN must not be treated as safe.
    Not a substitute for a pharmacist or doctor; no treatment advice.
    """
    try:
        checker = MedicineSafetyChecker(db)
        return await checker.check(body.medicine_ids, allergies=body.allergies)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


def _favourite_medicine_summary(medicine: Medicine) -> dict[str, Any]:
    """Minimal catalogue fields for favourites list (not clinical advice)."""
    return {
        "id": medicine.id,
        "name": medicine.name,
        "generic_name": medicine.generic_name,
        "brand_name": medicine.brand_name,
        "strength": medicine.strength,
        "dosage_form": medicine.dosage_form,
        "tga_artg_number": medicine.tga_artg_number,
        "schedule": medicine.schedule,
    }


async def _require_catalog_medicine(
    db: AsyncSession, medicine_id: int
) -> Medicine:
    if medicine_id < 1:
        raise HTTPException(status_code=400, detail="Invalid medicine_id")
    result = await db.execute(select(Medicine).where(Medicine.id == medicine_id))
    medicine = result.scalar_one_or_none()
    if not medicine:
        raise HTTPException(status_code=404, detail="Medicine not found")
    return medicine


@router.get("/favourites")
async def list_medicine_favourites(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    HN-MED-009 — list the authenticated user's favourite medicines.

    Bookmark only — not a prescription, TGA/PBS check, or clinical recommendation.
    Owner is always derived from the auth principal (never from client body).
    """
    result = await db.execute(
        select(MedicineFavourite, Medicine)
        .join(Medicine, Medicine.id == MedicineFavourite.medicine_id)
        .where(MedicineFavourite.user_id == current_user.id)
        .order_by(MedicineFavourite.created_at.desc())
    )
    rows = result.all()
    items = []
    for fav, med in rows:
        items.append(
            {
                **_favourite_medicine_summary(med),
                "favourited_at": fav.created_at.isoformat()
                if fav.created_at is not None
                else None,
            }
        )
    audit_log.info(
        "medicine_favourites_listed",
        extra={"user_id": current_user.id, "count": len(items)},
    )
    return {
        "favourites": items,
        "count": len(items),
        "note": (
            "User-saved medicine bookmarks only. "
            "Not a prescription, medication schedule, or clinical recommendation."
        ),
    }


@router.get("/{medicine_id}/favourite")
async def get_medicine_favourite_status(
    medicine_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """HN-MED-009 — whether the current user has favourited this medicine."""
    await _require_catalog_medicine(db, medicine_id)
    result = await db.execute(
        select(MedicineFavourite.id).where(
            MedicineFavourite.user_id == current_user.id,
            MedicineFavourite.medicine_id == medicine_id,
        )
    )
    is_fav = result.scalar_one_or_none() is not None
    return {
        "medicine_id": medicine_id,
        "is_favourite": is_fav,
    }


@router.post("/{medicine_id}/favourite")
async def add_medicine_favourite(
    medicine_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    HN-MED-009 — favourite a catalogue medicine for the authenticated user.

    Idempotent: repeating POST does not create duplicate rows.
    """
    await _require_catalog_medicine(db, medicine_id)
    existing = await db.execute(
        select(MedicineFavourite).where(
            MedicineFavourite.user_id == current_user.id,
            MedicineFavourite.medicine_id == medicine_id,
        )
    )
    fav = existing.scalar_one_or_none()
    created = False
    if fav is None:
        fav = MedicineFavourite(
            user_id=current_user.id,
            medicine_id=medicine_id,
        )
        db.add(fav)
        await db.commit()
        await db.refresh(fav)
        created = True
        audit_log.info(
            "medicine_favourite_added",
            extra={
                "user_id": current_user.id,
                "medicine_id": medicine_id,
                "favourite_id": fav.id,
            },
        )
    return {
        "medicine_id": medicine_id,
        "is_favourite": True,
        "created": created,
        "favourite_id": fav.id,
    }


@router.delete("/{medicine_id}/favourite")
async def remove_medicine_favourite(
    medicine_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    HN-MED-009 — remove favourite for the authenticated user only.

    Idempotent: deleting a non-favourite returns is_favourite=false safely.
    Never deletes another user's row (scoped by current_user.id).
    """
    if medicine_id < 1:
        raise HTTPException(status_code=400, detail="Invalid medicine_id")
    # Medicine may have been removed from catalogue; still allow unfavourite by id.
    result = await db.execute(
        select(MedicineFavourite).where(
            MedicineFavourite.user_id == current_user.id,
            MedicineFavourite.medicine_id == medicine_id,
        )
    )
    fav = result.scalar_one_or_none()
    removed = False
    if fav is not None:
        await db.delete(fav)
        await db.commit()
        removed = True
        audit_log.info(
            "medicine_favourite_removed",
            extra={"user_id": current_user.id, "medicine_id": medicine_id},
        )
    return {
        "medicine_id": medicine_id,
        "is_favourite": False,
        "removed": removed,
    }


@router.get("/barcode/{barcode}")
async def get_by_barcode(
    barcode: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(Medicine).where(Medicine.barcode == barcode))
    medicine = result.scalar_one_or_none()
    if not medicine:
        raise HTTPException(status_code=404, detail="Medicine not found for this barcode")
    return _to_dict(medicine)


@router.get("/{medicine_id}/explanation")
async def get_medicine_explanation(
    medicine_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Minimum patient-friendly explanation for a CONFIRMED catalog medicine_id.

    Distinguishes DATABASE-SOURCED facts from AI rephrasing.
    AI must not invent clinical facts; missing fields return the unavailable placeholder.
    Do not call for unconfirmed OCR text — only after catalog match → medicine_id.
    """
    if medicine_id < 1:
        raise HTTPException(status_code=400, detail="Invalid medicine_id")
    try:
        service = MedicineExplanationService(db)
        return await service.explain(medicine_id)
    except LookupError:
        raise HTTPException(
            status_code=404,
            detail="Medicine not found in catalog — cannot explain unconfirmed medicines",
        )


@router.get("/{medicine_id}")
async def get_medicine(
    medicine_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # v2: include field_sources / provenance (HN-MED-008)
    cache_key = f"medicine:v2:{medicine_id}"
    cached = await CacheService.get(cache_key)
    if cached is not None:
        return cached

    result = await db.execute(select(Medicine).where(Medicine.id == medicine_id))
    medicine = result.scalar_one_or_none()
    if not medicine:
        raise HTTPException(status_code=404, detail="Medicine not found")

    response = _to_dict(medicine)
    await CacheService.set(cache_key, response, ttl=MEDICINE_DETAIL_TTL)
    return response


@router.get("/ai-info/{name}")
async def get_ai_medicine_info(
    name: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    HN-MED-008 — catalogue-gated explanation bridge.

    Does NOT invent structured clinical fields for unknown names.
    Prefer GET /medicines/{id}/explanation for medicine detail.
    Ambiguous / unmatched names return an honest error (no fabricated record).
    """
    cleaned = (name or "").strip()
    if len(cleaned) < 2:
        raise HTTPException(status_code=400, detail="Medicine name too short")

    result = await db.execute(
        select(Medicine)
        .where(func.lower(Medicine.name) == cleaned.lower())
        .limit(5)
    )
    rows = list(result.scalars().all())
    if not rows:
        raise HTTPException(
            status_code=404,
            detail=(
                "Medicine not found in catalogue. "
                "AI cannot invent a medicine record or authoritative clinical fields."
            ),
        )
    if len(rows) > 1:
        raise HTTPException(
            status_code=400,
            detail=(
                "Ambiguous medicine name — select a confirmed catalogue medicine_id."
            ),
        )

    try:
        out = await MedicineExplanationService(db).explain(rows[0].id)
    except LookupError:
        raise HTTPException(
            status_code=404,
            detail="Medicine not found in catalogue — cannot invent clinical data",
        ) from None

    # Explicit envelope: never a flat inventable clinical map
    return {
        **out,
        "endpoint": "ai-info",
        "catalog_matched": True,
        "structured_clinical_from_ai": False,
        "legacy_note": (
            "This endpoint returns catalogue-grounded explanation only. "
            "Prefer GET /medicines/{id}/explanation for medicine detail."
        ),
    }


@router.get("/{medicine_id}/alternatives")
async def get_alternatives(
    medicine_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get generic alternatives and cost-saving options — Feature #15 & #28."""
    result = await db.execute(select(Medicine).where(Medicine.id == medicine_id))
    medicine = result.scalar_one_or_none()
    if not medicine:
        raise HTTPException(status_code=404, detail="Medicine not found")

    alternatives = await get_medicine_alternatives(medicine.name, medicine.generic_name)
    return {
        "medicine_id": medicine_id,
        "medicine_name": medicine.name,
        "generic_name": medicine.generic_name,
        "tga_registered": medicine.tga_registered,
        "schedule": medicine.schedule,
        "atc_code": medicine.atc_code,
        **alternatives,
    }


@router.get("/{medicine_id}/allergy-check")
async def check_medicine_allergy(
    medicine_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Check if a specific medicine conflicts with the user's allergies — Feature #12."""
    import json as _json
    result = await db.execute(select(Medicine).where(Medicine.id == medicine_id))
    medicine = result.scalar_one_or_none()
    if not medicine:
        raise HTTPException(status_code=404, detail="Medicine not found")

    allergies = []
    if current_user.allergies:
        try:
            parsed = _json.loads(current_user.allergies) if isinstance(current_user.allergies, str) else current_user.allergies
            allergies = parsed if isinstance(parsed, list) else []
        except Exception:
            pass

    if not allergies:
        return {"medicine": medicine.name, "safe": True, "alerts": [], "note": "No allergies recorded in your profile."}

    result = await check_allergy_conflicts([medicine.name], allergies)
    return {"medicine": medicine.name, **result}


def _nonempty(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str) and not value.strip():
        return False
    if isinstance(value, (list, dict)) and len(value) == 0:
        return False
    return True


def _field_source(value: Any) -> str:
    """Structured clinical fields are DB facts or unavailable — never AI-filled."""
    return "database" if _nonempty(value) else "unavailable"


def _to_dict(m: Medicine) -> dict:
    drug_class = m.drug_class or getattr(m, "therapeutic_class", None)
    composition = m.composition
    uses = m.uses
    consumer_information = m.consumer_information
    standard_dosage = m.standard_dosage
    side_effects = m.side_effects
    interactions = m.interactions
    contraindications = m.contraindications
    warnings = m.warnings
    storage = m.storage_instructions
    schedule = m.schedule
    pregnancy_category = m.pregnancy_category

    field_sources = {
        "name": _field_source(m.name),
        "generic_name": _field_source(m.generic_name),
        "composition": _field_source(composition),
        "drug_class": _field_source(drug_class),
        "uses": _field_source(uses),
        "consumer_information": _field_source(consumer_information),
        "standard_dosage": _field_source(standard_dosage),
        "side_effects": _field_source(side_effects),
        "interactions": _field_source(interactions),
        "contraindications": _field_source(contraindications),
        "warnings": _field_source(warnings),
        "storage": _field_source(storage),
        "au_schedule": _field_source(schedule),
        "pregnancy_category": _field_source(pregnancy_category),
        # Regulatory flags come only from catalogue columns (not LLM assertion)
        "tga_registered": "database",
        "pbs_code": _field_source(getattr(m, "pbs_code", None)),
        "tga_artg_number": _field_source(getattr(m, "tga_artg_number", None)),
    }

    return {
        "id": m.id,
        "name": m.name,
        "generic_name": m.generic_name,
        "composition": composition,
        "drug_class": drug_class,
        "uses": uses,
        "consumer_information": consumer_information,
        "standard_dosage": standard_dosage,
        "side_effects": side_effects,
        "interactions": interactions,
        "contraindications": contraindications,
        "warnings": warnings,
        "storage": storage,
        "tga_registered": bool(m.tga_registered) if m.tga_registered is not None else False,
        # Flutter reads 'au_schedule' — was incorrectly sent as 'schedule'
        "au_schedule": schedule,
        "manufacturer": m.manufacturer or m.sponsor,
        "pregnancy_category": pregnancy_category,
        # Catalogue metadata (identity/source), not CMI clinical authority
        "primary_source": getattr(m, "primary_source", None),
        "tga_artg_number": getattr(m, "tga_artg_number", None),
        "pbs_code": getattr(m, "pbs_code", None),
        "field_sources": field_sources,
        "provenance": {
            "structured_clinical": "database_only",
            "ai_may_complete_structured_fields": False,
            "labels": dict(_PROVENANCE_LABELS),
            "note": (
                "Structured clinical fields reflect the local medicine catalogue only. "
                "ARTG/PBS identifiers do not imply live TGA/CMI clinical documentation."
            ),
        },
    }
