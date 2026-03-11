import datetime as dt
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
    pattern_insight: str | None = None


class DailyFocusRequest(BaseModel):
    weekly_plan_id: UUID
    date: dt.date


class DailyFocusResponse(BaseModel):
    suggestions: list[str]
    nudge: str | None = None


class SuggestDailyIntentRequest(BaseModel):
    weekly_plan_id: UUID
    date: dt.date


class SuggestDailyIntentResponse(BaseModel):
    daily_intent: str


class SuggestIntentRequest(BaseModel):
    goal_id: UUID
    previous_plan_id: UUID | None = None


class SuggestIntentResponse(BaseModel):
    suggested_intent: str
