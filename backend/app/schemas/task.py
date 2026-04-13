import datetime as dt
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.task import EnergyType


class TaskCreate(BaseModel):
    weekly_plan_id: UUID
    title: str = Field(..., max_length=300)
    date: dt.date
    energy_type: EnergyType = EnergyType.deep
    description: Optional[str] = None
    start_time: Optional[dt.time] = None
    end_time: Optional[dt.time] = None
    quarter_id: Optional[UUID] = None


class TaskUpdate(BaseModel):
    title: Optional[str] = Field(None, max_length=300)
    date: Optional[dt.date] = None
    energy_type: Optional[EnergyType] = None
    description: Optional[str] = None
    start_time: Optional[dt.time] = None
    end_time: Optional[dt.time] = None
    skip_reason: Optional[str] = None
    quarter_id: Optional[UUID] = None


class CarryForwardRequest(BaseModel):
    task_ids: list[UUID]
    target_weekly_plan_id: UUID
    target_date: dt.date


class TaskResponse(BaseModel):
    id: UUID
    user_id: UUID
    weekly_plan_id: UUID
    quarter_id: UUID | None = None
    title: str
    date: dt.date
    completed: bool
    energy_type: EnergyType
    description: str | None = None
    start_time: dt.time | None = None
    end_time: dt.time | None = None
    skip_reason: str | None = None
    created_at: dt.datetime

    model_config = {"from_attributes": True}
