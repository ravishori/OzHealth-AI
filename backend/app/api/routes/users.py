from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from app.core.log_decorator import LoggedAPIRoute
from sqlalchemy.ext.asyncio import AsyncSession
import json

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.schemas.user import UserUpdate, UserResponse
from app.utils.storage import save_file
from app.services.cache_service import CacheService, USER_PROFILE_TTL
from app.core.logging_config import audit_log

router = APIRouter(route_class=LoggedAPIRoute)


@router.get("/me", response_model=UserResponse)
async def get_profile(current_user: User = Depends(get_current_user)):
    cache_key = f"user:{current_user.id}:profile"
    cached = await CacheService.get(cache_key)
    if cached is not None:
        return cached

    response = _user_to_response(current_user)
    await CacheService.set(cache_key, response, ttl=USER_PROFILE_TTL)
    return response


@router.put("/me", response_model=UserResponse)
async def update_profile(
    updates: UserUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if updates.name is not None:
        current_user.name = updates.name
    if updates.age is not None:
        current_user.age = updates.age
    if updates.gender is not None:
        current_user.gender = updates.gender
    if updates.blood_group is not None:
        current_user.blood_group = updates.blood_group
    if updates.health_conditions is not None:
        # Store as JSON string — EncryptedText TypeDecorator encrypts automatically
        current_user.health_conditions = json.dumps(updates.health_conditions)
    if updates.allergies is not None:
        current_user.allergies = json.dumps(updates.allergies)
    if updates.lifestyle_preferences is not None:
        current_user.lifestyle_preferences = json.dumps(updates.lifestyle_preferences)
    if updates.fcm_token is not None:
        current_user.fcm_token = updates.fcm_token

    await db.commit()
    await db.refresh(current_user)

    # Invalidate cached profile
    await CacheService.delete(f"user:{current_user.id}:profile")

    audit_log.info("profile_updated", extra={"user_id": current_user.id})

    return _user_to_response(current_user)


@router.post("/me/photo")
async def upload_profile_photo(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    url = await save_file(file, folder=f"profiles/{current_user.id}")
    current_user.profile_image_url = url
    await db.commit()

    # Invalidate cached profile
    await CacheService.delete(f"user:{current_user.id}:profile")

    return {"profile_image_url": url}


def _user_to_response(user: User) -> dict:
    # health_conditions and allergies are decrypted by EncryptedText TypeDecorator
    def _parse_json(value):
        if not value:
            return []
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return []

    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "phone": user.phone,
        "age": user.age,
        "gender": user.gender,
        "blood_group": user.blood_group,
        "health_conditions": _parse_json(user.health_conditions),
        "allergies": _parse_json(user.allergies),
        "profile_image_url": user.profile_image_url,
        "is_verified": user.is_verified,
        "created_at": user.created_at,
    }
