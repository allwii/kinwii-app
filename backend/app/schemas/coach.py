import datetime as dt
from uuid import UUID

from pydantic import BaseModel, Field


class CoachMessageSend(BaseModel):
    content: str = Field(..., min_length=1, max_length=2000)


class CoachMessageResponse(BaseModel):
    id: UUID
    user_id: UUID
    role: str
    content: str
    created_at: dt.datetime

    model_config = {"from_attributes": True}


class CoachReply(BaseModel):
    user_message: CoachMessageResponse
    assistant_message: CoachMessageResponse
