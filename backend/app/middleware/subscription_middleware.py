from datetime import datetime, timezone

from fastapi import Depends, HTTPException, status

from app.middleware.auth_middleware import get_current_user
from app.models.user import SubscriptionTier, User

# Free trial duration — all features, then hard paywall.
TRIAL_DAYS = 3


def _is_pro(user: User) -> bool:
    """Check if a user currently has Pro access (active subscription or trial)."""
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


def _is_trial_expired(user: User) -> bool:
    """Trial has expired and user has no paid subscription."""
    now = datetime.now(timezone.utc)
    return (
        user.trial_end_date is not None
        and user.trial_end_date <= now
        and not user.subscription_expires_at
    )


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


def require_active_access(
    current_user: User = Depends(get_current_user),
) -> User:
    """Dependency that raises 402 if the trial has expired and the user
    has no active subscription. Backend safety net for the hard paywall.
    """
    if _is_trial_expired(current_user):
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Your trial has expired. Subscribe to continue.",
        )
    return current_user
