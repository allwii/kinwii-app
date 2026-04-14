from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, status

from app.middleware.auth_middleware import get_current_user
from app.models.user import SubscriptionTier, User

# AI features are free for the first 3 days of the trial; core app for 7.
AI_TRIAL_DAYS = 3


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


def _is_ai_trial_active(user: User) -> bool:
    """AI features are free for the first AI_TRIAL_DAYS days only."""
    if user.trial_start_date is None:
        return False
    now = datetime.now(timezone.utc)
    ai_cutoff = user.trial_start_date + timedelta(days=AI_TRIAL_DAYS)
    return now < ai_cutoff


def has_ai_access(user: User) -> bool:
    """User can use AI if they are a paying Pro subscriber OR within the AI trial window."""
    return _is_pro(user) or _is_ai_trial_active(user)


def _is_trial_expired(user: User) -> bool:
    """Full trial (7 days) has expired and user has no paid subscription."""
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


def require_ai_access(
    current_user: User = Depends(get_current_user),
) -> User:
    """Dependency that raises 403 if AI trial (3 days) has expired and user is not Pro."""
    if not has_ai_access(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="AI features require Kinwii Pro.",
        )
    return current_user


def require_active_access(
    current_user: User = Depends(get_current_user),
) -> User:
    """Dependency that raises 402 if the full trial (7 days) has expired
    and the user has no active subscription. Backend safety net for the
    hard paywall.
    """
    if _is_trial_expired(current_user):
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Your trial has expired. Subscribe to continue.",
        )
    return current_user
