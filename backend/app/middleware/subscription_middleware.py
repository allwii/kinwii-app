from datetime import datetime, timezone

from fastapi import Depends, HTTPException, status

from app.middleware.auth_middleware import get_current_user
from app.models.user import SubscriptionTier, User


def _is_pro(user: User) -> bool:
    """Check if a user currently has Pro access (active subscription or trial)."""
    # TEMPORARILY DISABLED — re-enable when paywall is ready
    return True

    now = datetime.now(timezone.utc)

    # Active paid subscription
    if (
        user.subscription_tier == SubscriptionTier.pro
        and user.subscription_expires_at
        and user.subscription_expires_at > now
    ):
        return True

    # Active trial (pro tier + trial not expired)
    if (
        user.subscription_tier == SubscriptionTier.pro
        and user.trial_end_date
        and user.trial_end_date > now
        and not user.subscription_expires_at
    ):
        return True

    return False


def get_user_tier(
    current_user: User = Depends(get_current_user),
) -> str:
    """Return the user's effective tier ('pro' or 'free')."""
    return "pro" if _is_pro(current_user) else "free"


def require_pro(
    current_user: User = Depends(get_current_user),
) -> User:
    """Dependency that raises 403 if the user is not on the Pro tier."""
    if not _is_pro(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This feature requires Kinwii Pro.",
        )
    return current_user
