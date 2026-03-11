import datetime as dt
from uuid import UUID

from pydantic import BaseModel, Field


class DailyIntentCreate(BaseModel):
    weekly_plan_id: UUID | None = None
    date: dt.date
    intent: str = Field(..., min_length=1, max_length=500)


class DailyIntentUpdate(BaseModel):
    intent: str | None = Field(None, min_length=1, max_length=500)
    honored: bool | None = None
    note: str | None = None


class DailyIntentResponse(BaseModel):
    id: UUID
    user_id: UUID
    weekly_plan_id: UUID | None
    date: dt.date
    intent: str
    honored: bool | None
    note: str | None
    created_at: dt.datetime

    model_config = {"from_attributes": True}
