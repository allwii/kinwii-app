import datetime as dt
from uuid import UUID

from pydantic import BaseModel


class CoachBriefingResponse(BaseModel):
    """Response payload for GET /coach/briefing.

    `body` and `followups` are populated for Pro users; for free users they
    are `None` and `[]` respectively so the client can render a teaser with a
    paywall CTA.
    """

    id: UUID
    date: dt.date
    headline: str
    body: str | None = None
    followups: list[str] = []
    is_pro: bool
    created_at: dt.datetime

    model_config = {"from_attributes": True}
