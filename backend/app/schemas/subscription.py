from datetime import datetime

from pydantic import BaseModel


class SubscriptionStatus(BaseModel):
    tier: str
    is_trial: bool
    trial_end_date: datetime | None = None
    subscription_expires_at: datetime | None = None

    model_config = {"from_attributes": True}
