from pydantic import BaseModel


class FCMTokenRegister(BaseModel):
    fcm_token: str


class NotificationPreferences(BaseModel):
    morning_focus: bool = True
    evening_reflect: bool = True
    midweek_progress: bool = True
    quiet_hours_start: int = 22  # hour (0-23)
    quiet_hours_end: int = 7  # hour (0-23)

    model_config = {"from_attributes": True}
