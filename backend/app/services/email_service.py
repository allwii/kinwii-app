"""Email service — sends transactional emails via Resend."""

import logging

import resend

from app.config import settings

logger = logging.getLogger(__name__)

resend.api_key = settings.RESEND_API_KEY

FROM_ADDRESS = "Kinwii <kelvin@kinwii.com>"


def send_reset_code_email(to_email: str, code: str) -> None:
    """Send a 6-digit password reset code to the user."""
    try:
        resend.Emails.send(
            {
                "from": FROM_ADDRESS,
                "to": [to_email],
                "subject": "Your Kinwii password reset code",
                "html": f"""
                    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 400px; margin: 0 auto; padding: 32px;">
                        <h2 style="color: #1A1A1A; margin-bottom: 8px;">Password Reset</h2>
                        <p style="color: #6B7280; margin-bottom: 24px;">Use this code to reset your password. It expires in 10 minutes.</p>
                        <div style="background: #F0FBE8; border-radius: 12px; padding: 24px; text-align: center; margin-bottom: 24px;">
                            <span style="font-size: 32px; font-weight: 700; letter-spacing: 8px; color: #438624;">{code}</span>
                        </div>
                        <p style="color: #9CA3AF; font-size: 13px;">If you didn't request this, you can safely ignore this email.</p>
                    </div>
                """,
            }
        )
        logger.info("Reset code email sent to %s", to_email)
    except Exception as e:
        logger.error("Failed to send reset email to %s: %s", to_email, e)
        raise
