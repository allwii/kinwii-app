from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class MissionUpdate(BaseModel):
    statement: str = Field(..., min_length=1, max_length=500)


class MissionResponse(BaseModel):
    id: UUID
    user_id: UUID
    statement: str
    created_at: datetime
    updated_at: datetime | None

    model_config = {"from_attributes": True}


class RoleCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None


class RoleUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = None


class RoleResponse(BaseModel):
    id: UUID
    user_id: UUID
    name: str
    description: str | None
    created_at: datetime

    model_config = {"from_attributes": True}
