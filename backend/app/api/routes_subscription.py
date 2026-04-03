import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.middleware.subscription_middleware import get_user_tier
from app.models.user import SubscriptionTier, User
from app.schemas.subscription import SubscriptionStatus

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/subscription", tags=["subscription"])


@router.get("/status", response_model=SubscriptionStatus)
async def get_subscription_status(
    current_user: User = Depends(get_current_user),
    tier: str = Depends(get_user_tier),
):
    now = datetime.now(timezone.utc)
    is_trial = (
        tier == "pro"
        and current_user.trial_end_date is not None
        and current_user.trial_end_date > now
        and not current_user.subscription_expires_at
    )
    return SubscriptionStatus(
        tier=tier,
        is_trial=is_trial,
        trial_end_date=current_user.trial_end_date,
        subscription_expires_at=current_user.subscription_expires_at,
    )


@router.post("/webhook/revenuecat")
async def revenuecat_webhook(
    request: Request,
    db: Session = Depends(get_db),
    authorization: str | None = Header(default=None),
):
    """Handle RevenueCat server-to-server webhook notifications.

    See https://www.revenuecat.com/docs/integrations/webhooks
    """
    # Verify webhook auth header matches our secret
    expected = getattr(settings, "REVENUECAT_WEBHOOK_SECRET", None)
    if expected and authorization != f"Bearer {expected}":
        raise HTTPException(status_code=401, detail="Invalid webhook secret")

    body = await request.json()
    event = body.get("event", {})
    event_type = event.get("type", "")
    app_user_id = event.get("app_user_id", "")

    if not app_user_id:
        logger.warning("RevenueCat webhook missing app_user_id")
        return {"status": "ignored"}

    user = db.query(User).filter(User.id == app_user_id).first()
    if not user:
        logger.warning("RevenueCat webhook: user %s not found", app_user_id)
        return {"status": "ignored"}

    if event_type in (
        "INITIAL_PURCHASE",
        "RENEWAL",
        "PRODUCT_CHANGE",
        "UNCANCELLATION",
    ):
        expiration = event.get("expiration_at_ms")
        if expiration:
            user.subscription_tier = SubscriptionTier.pro
            user.subscription_expires_at = datetime.fromtimestamp(
                expiration / 1000, tz=timezone.utc
            )
            logger.info("User %s upgraded to Pro until %s", app_user_id, user.subscription_expires_at)

    elif event_type in ("CANCELLATION", "EXPIRATION"):
        user.subscription_tier = SubscriptionTier.free
        user.subscription_expires_at = None
        logger.info("User %s downgraded to Free", app_user_id)

    db.commit()
    return {"status": "ok"}
