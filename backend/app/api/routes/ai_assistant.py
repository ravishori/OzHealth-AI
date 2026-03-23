from fastapi import APIRouter, Depends, HTTPException
from app.core.log_decorator import LoggedAPIRoute
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional, List
import json
from datetime import datetime, timezone

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.ai_conversation import AIConversation
from app.services.ai_service import chat_with_health_assistant

router = APIRouter(route_class=LoggedAPIRoute)


class ChatMessage(BaseModel):
    message: str
    conversation_id: Optional[int] = None
    context_type: str = "general"


class HealthGuidanceRequest(BaseModel):
    topic: str  # nutrition, exercise, sleep, preventive
    context: Optional[str] = None


@router.post("/chat")
async def chat(
    req: ChatMessage,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Load or create conversation
    messages = []
    conversation = None

    if req.conversation_id:
        result = await db.execute(
            select(AIConversation).where(
                AIConversation.id == req.conversation_id,
                AIConversation.user_id == current_user.id,
            )
        )
        conversation = result.scalar_one_or_none()
        if conversation:
            messages = json.loads(conversation.messages)

    # Add user message
    messages.append({
        "role": "user",
        "content": req.message,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })

    # Build user context for AI
    user_context = {
        "name": current_user.name,
        "age": current_user.age,
        "gender": current_user.gender,
        "blood_group": current_user.blood_group,
        "health_conditions": json.loads(current_user.health_conditions) if current_user.health_conditions else [],
        "allergies": json.loads(current_user.allergies) if current_user.allergies else [],
    }

    # Get AI response
    ai_response = await chat_with_health_assistant(messages, user_context)

    # Add assistant response
    messages.append({
        "role": "assistant",
        "content": ai_response,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })

    # Save conversation
    if conversation:
        conversation.messages = json.dumps(messages)
        if not conversation.title:
            conversation.title = req.message[:100]
    else:
        conversation = AIConversation(
            user_id=current_user.id,
            title=req.message[:100],
            messages=json.dumps(messages),
            context_type=req.context_type,
        )
        db.add(conversation)

    await db.commit()
    await db.refresh(conversation)

    return {
        "conversation_id": conversation.id,
        "response": ai_response,
        "message_count": len(messages),
    }


@router.post("/health-guidance")
async def get_health_guidance(
    req: HealthGuidanceRequest,
    current_user: User = Depends(get_current_user),
):
    user_context = {
        "name": current_user.name,
        "age": current_user.age,
        "gender": current_user.gender,
        "health_conditions": json.loads(current_user.health_conditions) if current_user.health_conditions else [],
        "allergies": json.loads(current_user.allergies) if current_user.allergies else [],
    }

    guidance = await chat_with_health_assistant(
        messages=[{
            "role": "user",
            "content": f"Provide personalised health guidance on: {req.topic}. {req.context or ''}",
        }],
        user_context=user_context,
        system_override=f"You are a health advisor specialising in {req.topic}. Provide evidence-based, Australia-specific health guidance.",
    )

    return {"topic": req.topic, "guidance": guidance}


@router.get("/conversations")
async def list_conversations(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(AIConversation)
        .where(AIConversation.user_id == current_user.id)
        .order_by(AIConversation.updated_at.desc())
        .limit(20)
    )
    convs = result.scalars().all()
    return [
        {
            "id": c.id,
            "title": c.title,
            "context_type": c.context_type,
            "message_count": len(json.loads(c.messages)) if c.messages else 0,
            "created_at": c.created_at,
            "updated_at": c.updated_at,
        }
        for c in convs
    ]


@router.get("/conversations/{conv_id}")
async def get_conversation(
    conv_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(AIConversation).where(
            AIConversation.id == conv_id,
            AIConversation.user_id == current_user.id,
        )
    )
    conv = result.scalar_one_or_none()
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return {
        "id": conv.id,
        "title": conv.title,
        "context_type": conv.context_type,
        "messages": json.loads(conv.messages) if conv.messages else [],
        "created_at": conv.created_at,
    }
