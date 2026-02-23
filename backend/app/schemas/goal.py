from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, Field


class GoalCreate(BaseModel):
    title: str = Field(..., max_length=200)
    why: str | None = None
    start_date: date
    end_date: date


class GoalUpdate(BaseModel):
    title: str | None = Field(None, max_length=200)
    why: str | None = None
    progress_percent: int | None = Field(None, ge=0, le=100)


class GoalResponse(BaseModel):
    id: UUID
    user_id: UUID
    title: str
    why: str | None
    start_date: date
    end_date: date
    progress_percent: int
    created_at: datetime
    updated_at: datetime | None

    model_config = {"from_attributes": True}
