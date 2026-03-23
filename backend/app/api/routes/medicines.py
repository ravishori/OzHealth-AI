from fastapi import APIRouter, Depends, HTTPException, Query
from app.core.log_decorator import LoggedAPIRoute
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, func
from typing import Optional

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.medicine import Medicine
from app.services.ai_service import get_medicine_info_from_ai
from app.services.cache_service import CacheService, MEDICINE_SEARCH_TTL, MEDICINE_DETAIL_TTL

router = APIRouter(route_class=LoggedAPIRoute)


@router.get("/search")
async def search_medicines(
    q: str = Query(..., min_length=2),
    limit: int = Query(20, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cache_key = f"medicines:search:{q.lower()}:{limit}"
    cached = await CacheService.get(cache_key)
    if cached is not None:
        return cached

    result = await db.execute(
        select(Medicine).where(
            or_(
                func.lower(Medicine.name).contains(q.lower()),
                func.lower(Medicine.generic_name).contains(q.lower()),
            )
        ).limit(limit)
    )
    medicines = result.scalars().all()

    if not medicines:
        ai_info = await get_medicine_info_from_ai(q)
        response = {"results": [ai_info] if ai_info else [], "source": "ai"}
        # Don't cache AI fallback results (they may be imprecise)
        return response

    response = {"results": [_to_dict(m) for m in medicines], "source": "database"}
    await CacheService.set(cache_key, response, ttl=MEDICINE_SEARCH_TTL)
    return response


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


@router.get("/{medicine_id}")
async def get_medicine(
    medicine_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cache_key = f"medicine:{medicine_id}"
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
    current_user: User = Depends(get_current_user),
):
    info = await get_medicine_info_from_ai(name)
    if not info:
        raise HTTPException(status_code=404, detail="Could not retrieve medicine information")
    return info


def _to_dict(m: Medicine) -> dict:
    return {
        "id": m.id,
        "name": m.name,
        "generic_name": m.generic_name,
        "composition": m.composition,
        "drug_class": m.drug_class,
        "standard_dosage": m.standard_dosage,
        "side_effects": m.side_effects,
        "interactions": m.interactions,
        "contraindications": m.contraindications,
        "warnings": m.warnings,
        "tga_registered": m.tga_registered,
        "schedule": m.schedule,
    }
