from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class ReflectionCreate(BaseModel):
    weekly_plan_id: UUID
    moved_needle: str | None = None
    drained_energy: str | None = None
    stop_doing: str | None = None
    focus_next_week: str | None = None


class ReflectionUpdate(BaseModel):
    moved_needle: str | None = None
    drained_energy: str | None = None
    stop_doing: str | None = None
    focus_next_week: str | None = None


class ReflectionResponse(BaseModel):
    id: UUID
    user_id: UUID
    weekly_plan_id: UUID
    moved_needle: str | None
    drained_energy: str | None
    stop_doing: str | None
    focus_next_week: str | None
    ai_summary: str | None
    ai_focus_recommendation: str | None
    ai_pattern_insight: str | None
    created_at: datetime

    model_config = {"from_attributes": True}
