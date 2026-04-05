"""Notification endpoints — FCM registration and notification preferences."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.models.user import User
from app.schemas.notification import FCMTokenRegister, NotificationPreferences

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.post("/register-token", status_code=204)
async def register_fcm_token(
    body: FCMTokenRegister,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    current_user.fcm_token = body.fcm_token
    db.commit()


@router.get("/preferences", response_model=NotificationPreferences)
async def get_preferences(
    current_user: User = Depends(get_current_user),
):
    return NotificationPreferences(
        morning_focus=current_user.notify_morning_focus,
        evening_reflect=current_user.notify_evening_reflect,
        midweek_progress=current_user.notify_midweek_progress,
    )


@router.put("/preferences", response_model=NotificationPreferences)
async def update_preferences(
    body: NotificationPreferences,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    current_user.notify_morning_focus = body.morning_focus
    current_user.notify_evening_reflect = body.evening_reflect
    current_user.notify_midweek_progress = body.midweek_progress
    db.commit()
    return NotificationPreferences(
        morning_focus=current_user.notify_morning_focus,
        evening_reflect=current_user.notify_evening_reflect,
        midweek_progress=current_user.notify_midweek_progress,
    )
