from uuid import UUID

from pydantic import BaseModel


class AlignWeekRequest(BaseModel):
    weekly_plan_id: UUID


class AlignWeekResponse(BaseModel):
    suggestions: list[str]


class SummarizeReflectionRequest(BaseModel):
    reflection_id: UUID


class SummarizeReflectionResponse(BaseModel):
    summary: str
    focus_recommendation: str
