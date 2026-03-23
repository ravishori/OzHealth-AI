from fastapi import APIRouter, Depends, HTTPException
from app.core.log_decorator import LoggedAPIRoute
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import json

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.family_member import FamilyMember
from app.schemas.family import FamilyMemberCreate, FamilyMemberUpdate, FamilyMemberResponse

router = APIRouter(route_class=LoggedAPIRoute)


@router.get("/", response_model=list[FamilyMemberResponse])
async def list_family(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(FamilyMember).where(
            FamilyMember.user_id == current_user.id,
            FamilyMember.is_active == True,
        )
    )
    members = result.scalars().all()
    return [_to_response(m) for m in members]


@router.post("/", response_model=FamilyMemberResponse)
async def create_family_member(
    data: FamilyMemberCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = FamilyMember(
        user_id=current_user.id,
        name=data.name,
        relationship=data.relationship,
        age=data.age,
        gender=data.gender,
        blood_group=data.blood_group,
        medical_conditions=json.dumps(data.medical_conditions or []),
        allergies=json.dumps(data.allergies or []),
        notes=data.notes,
    )
    db.add(member)
    await db.commit()
    await db.refresh(member)
    return _to_response(member)


@router.get("/{member_id}", response_model=FamilyMemberResponse)
async def get_family_member(
    member_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = await _get_member(db, member_id, current_user.id)
    return _to_response(member)


@router.put("/{member_id}", response_model=FamilyMemberResponse)
async def update_family_member(
    member_id: int,
    data: FamilyMemberUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = await _get_member(db, member_id, current_user.id)

    if data.name is not None:
        member.name = data.name
    if data.relationship is not None:
        member.relationship = data.relationship
    if data.age is not None:
        member.age = data.age
    if data.gender is not None:
        member.gender = data.gender
    if data.blood_group is not None:
        member.blood_group = data.blood_group
    if data.medical_conditions is not None:
        member.medical_conditions = json.dumps(data.medical_conditions)
    if data.allergies is not None:
        member.allergies = json.dumps(data.allergies)
    if data.notes is not None:
        member.notes = data.notes

    await db.commit()
    await db.refresh(member)
    return _to_response(member)


@router.delete("/{member_id}")
async def delete_family_member(
    member_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member = await _get_member(db, member_id, current_user.id)
    member.is_active = False
    await db.commit()
    return {"message": "Family member removed"}


async def _get_member(db: AsyncSession, member_id: int, user_id: int) -> FamilyMember:
    result = await db.execute(
        select(FamilyMember).where(
            FamilyMember.id == member_id,
            FamilyMember.user_id == user_id,
        )
    )
    member = result.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=404, detail="Family member not found")
    return member


def _to_response(m: FamilyMember) -> dict:
    return {
        "id": m.id,
        "user_id": m.user_id,
        "name": m.name,
        "relationship": m.relationship,
        "age": m.age,
        "gender": m.gender,
        "blood_group": m.blood_group,
        "medical_conditions": json.loads(m.medical_conditions) if m.medical_conditions else [],
        "allergies": json.loads(m.allergies) if m.allergies else [],
        "notes": m.notes,
        "created_at": m.created_at,
    }
