from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class UserCreate(BaseModel):
    email: str = Field(..., min_length=3)
    password: str = Field(..., min_length=8)
    device_id: str | None = None


class UserLogin(BaseModel):
    email: str
    password: str


class DeviceRegisterRequest(BaseModel):
    device_id: str = Field(..., min_length=8)


class LinkEmailRequest(BaseModel):
    email: str = Field(..., min_length=3)
    password: str = Field(..., min_length=8)
    name: str | None = Field(None, min_length=1, max_length=100)


class UserResponse(BaseModel):
    id: UUID
    email: str | None = None
    name: str | None = None
    created_at: datetime
    subscription_tier: str = "free"
    trial_end_date: datetime | None = None
    subscription_expires_at: datetime | None = None
    auto_move_tasks: bool = False

    model_config = {"from_attributes": True}


class UserProfileUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    auto_move_tasks: bool | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=8)


class ForgotPasswordRequest(BaseModel):
    email: str


class ResetPasswordRequest(BaseModel):
    email: str
    code: str = Field(..., min_length=6, max_length=6)
    new_password: str = Field(..., min_length=8)


class MessageResponse(BaseModel):
    message: str


class GoogleSignInRequest(BaseModel):
    id_token: str
