from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime


class ChatMessage(BaseModel):
    role: str   # "user" | "assistant"
    content: str


class ChatRequest(BaseModel):
    message: str
    conversation_id: Optional[int] = None
    context_type: str = "general"  # general, prescription, health, medication


class ChatResponse(BaseModel):
    conversation_id: int
    reply: str
    title: Optional[str] = None


class HealthGuidanceRequest(BaseModel):
    query: str
    metric_type: Optional[str] = None  # blood_pressure, blood_sugar, weight, etc.
    recent_values: Optional[List[float]] = None


class ConversationSummary(BaseModel):
    id: int
    title: Optional[str] = None
    context_type: str
    last_message: Optional[str] = None
    message_count: int = 0
    updated_at: datetime

    class Config:
        from_attributes = True


class ConversationDetail(BaseModel):
    id: int
    title: Optional[str] = None
    context_type: str
    messages: List[Any] = []
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
