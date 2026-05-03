"""Feedback endpoint — sends user feedback to kelvin@kinwii.com via Resend."""

import logging

import resend
from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.config import settings
from app.middleware.auth_middleware import get_current_user
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/feedback", tags=["feedback"])

resend.api_key = settings.RESEND_API_KEY

FEEDBACK_TO = "kelvin@kinwii.com"


class FeedbackRequest(BaseModel):
    message: str
    email: str | None = None  # Optional contact email from anonymous users


class FeedbackResponse(BaseModel):
    message: str


@router.post("", response_model=FeedbackResponse)
async def submit_feedback(
    body: FeedbackRequest,
    current_user: User = Depends(get_current_user),
):
    contact_email = current_user.email or body.email
    user_label = contact_email or current_user.name or str(current_user.id)[:8]
    reply_to = [contact_email] if contact_email else []
    try:
        resend.Emails.send(
            {
                "from": "Kinwii <feedback@kinwii.com>",
                "to": [FEEDBACK_TO],
                **({"reply_to": reply_to} if reply_to else {}),
                "subject": f"Kinwii Feedback from {user_label}",
                "html": f"""
                    <div style="font-family: -apple-system, sans-serif; max-width: 500px; padding: 24px;">
                        <h3>Feedback from {user_label}</h3>
                        <p style="white-space: pre-wrap; line-height: 1.6;">{body.message}</p>
                        <hr style="border: none; border-top: 1px solid #E5E7EB; margin: 16px 0;">
                        <p style="color: #9CA3AF; font-size: 12px;">
                            User ID: {current_user.id}<br>
                            Name: {current_user.name or 'Not set'}<br>
                            Email: {contact_email or 'Not provided'}
                        </p>
                    </div>
                """,
            }
        )
        logger.info("Feedback email sent from user %s", current_user.id)
    except Exception as e:
        logger.error("Failed to send feedback email: %s", e)

    return FeedbackResponse(message="Thank you for your feedback!")
