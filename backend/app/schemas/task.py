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


class TaskUpdate(BaseModel):
    title: Optional[str] = Field(None, max_length=300)
    date: Optional[dt.date] = None
    energy_type: Optional[EnergyType] = None


class TaskResponse(BaseModel):
    id: UUID
    user_id: UUID
    weekly_plan_id: UUID
    title: str
    date: dt.date
    completed: bool
    energy_type: EnergyType
    created_at: dt.datetime

    model_config = {"from_attributes": True}
