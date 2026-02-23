from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, Field


class WeeklyPlanCreate(BaseModel):
    quarter_id: UUID | None = None
    week_start_date: date
    intent: str = Field(..., min_length=1)


class WeeklyPlanUpdate(BaseModel):
    intent: str | None = None
    quarter_id: UUID | None = None


class WeeklyPlanResponse(BaseModel):
    id: UUID
    user_id: UUID
    quarter_id: UUID | None
    week_start_date: date
    intent: str
    progress_percent: int
    created_at: datetime

    model_config = {"from_attributes": True}
