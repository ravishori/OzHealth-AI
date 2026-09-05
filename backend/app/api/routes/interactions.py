"""
Drug Interaction Check — Feature #17 (basic) + #22 (advanced)
POST /api/v1/interactions/check
"""
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from typing import Optional

from app.core.log_decorator import LoggedAPIRoute
from app.core.deps import get_current_user
from app.models.user import User
from app.services.ai_service import check_drug_interactions, detect_duplicate_medicines

router = APIRouter(route_class=LoggedAPIRoute)


class InteractionCheckRequest(BaseModel):
    medicines: list[str] = Field(..., min_items=2, description="List of medicine names to check")
    include_duplicate_check: bool = True


@router.post("/check")
async def check_interactions(
    req: InteractionCheckRequest,
    current_user: User = Depends(get_current_user),
):
    """Check drug interactions between multiple medicines with risk scoring."""
    user_context = {}
    if current_user.age:
        user_context["age"] = current_user.age
    if current_user.health_conditions:
        import json as _json
        try:
            conds = _json.loads(current_user.health_conditions) if isinstance(current_user.health_conditions, str) else current_user.health_conditions
            user_context["conditions"] = conds if isinstance(conds, list) else []
        except Exception:
            pass

    interaction_result = await check_drug_interactions(req.medicines, user_context)

    duplicate_result = None
    if req.include_duplicate_check and len(req.medicines) >= 2:
        duplicate_result = await detect_duplicate_medicines(req.medicines)

    return {
        "medicines_checked": req.medicines,
        "interaction_analysis": interaction_result,
        "duplicate_check": duplicate_result,
    }
