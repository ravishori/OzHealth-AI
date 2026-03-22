from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
import json

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.schemas.user import UserUpdate, UserResponse
from app.utils.storage import save_file

router = APIRouter()


@router.get("/me", response_model=UserResponse)
async def get_profile(current_user: User = Depends(get_current_user)):
    return _user_to_response(current_user)


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
        current_user.health_conditions = json.dumps(updates.health_conditions)
    if updates.allergies is not None:
        current_user.allergies = json.dumps(updates.allergies)
    if updates.lifestyle_preferences is not None:
        current_user.lifestyle_preferences = json.dumps(updates.lifestyle_preferences)
    if updates.fcm_token is not None:
        current_user.fcm_token = updates.fcm_token

    await db.commit()
    await db.refresh(current_user)
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
    return {"profile_image_url": url}


def _user_to_response(user: User) -> dict:
    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "phone": user.phone,
        "age": user.age,
        "gender": user.gender,
        "blood_group": user.blood_group,
        "health_conditions": json.loads(user.health_conditions) if user.health_conditions else [],
        "allergies": json.loads(user.allergies) if user.allergies else [],
        "profile_image_url": user.profile_image_url,
        "is_verified": user.is_verified,
        "created_at": user.created_at,
    }
