import logging
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.middleware.auth_middleware import (
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.models.user import SubscriptionTier, User
from app.schemas.user import (
    ForgotPasswordRequest,
    GoogleSignInRequest,
    MessageResponse,
    ResetPasswordRequest,
    TokenResponse,
    UserCreate,
    UserProfileUpdate,
    UserResponse,
)
from app.services.email_service import send_reset_code_email

logger = logging.getLogger(__name__)

# All valid Google client IDs (iOS, Android, Web) for token verification
_GOOGLE_CLIENT_IDS = set(
    cid
    for cid in [
        settings.GOOGLE_CLIENT_ID_IOS,
        settings.GOOGLE_CLIENT_ID_ANDROID,
        settings.GOOGLE_CLIENT_ID_WEB,
    ]
    if cid
)

router = APIRouter(prefix="/auth", tags=["auth"])

TRIAL_DAYS = 7


@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(body: UserCreate, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == body.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )
    now = datetime.now(timezone.utc)
    user = User(
        email=body.email,
        hashed_password=hash_password(body.password),
        subscription_tier=SubscriptionTier.pro,
        trial_start_date=now,
        trial_end_date=now + timedelta(days=TRIAL_DAYS),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token(user.id)
    return TokenResponse(access_token=token)


@router.post("/login", response_model=TokenResponse)
async def login(body: UserCreate, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == body.email).first()
    if not user or not verify_password(body.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )
    token = create_access_token(user.id)
    return TokenResponse(access_token=token)


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    return current_user


@router.delete("/me", status_code=204)
async def delete_me(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Permanently delete the current user and all associated data."""
    # Use raw SQL DELETE to let database-level ON DELETE CASCADE handle cleanup
    db.execute(text("DELETE FROM users WHERE id = :uid"), {"uid": str(current_user.id)})
    db.commit()


@router.put("/me", response_model=UserResponse)
async def update_me(
    body: UserProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.name is not None:
        current_user.name = body.name
    if body.auto_move_tasks is not None:
        current_user.auto_move_tasks = body.auto_move_tasks
    db.commit()
    db.refresh(current_user)
    return current_user


RESET_CODE_EXPIRY_MINUTES = 10


@router.post("/forgot-password", response_model=MessageResponse)
async def forgot_password(body: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """Send a 6-digit reset code to the user's email via Resend."""
    msg = "If that email is registered, a reset code has been sent."
    user = db.query(User).filter(User.email == body.email).first()
    if not user:
        # Don't reveal whether email exists
        return MessageResponse(message=msg)

    # Generate 6-digit code
    code = str(secrets.randbelow(900000) + 100000)
    user.reset_code = hash_password(code)
    user.reset_code_expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=RESET_CODE_EXPIRY_MINUTES
    )
    db.commit()

    send_reset_code_email(user.email, code)
    return MessageResponse(message=msg)


@router.post("/reset-password", response_model=MessageResponse)
async def reset_password(body: ResetPasswordRequest, db: Session = Depends(get_db)):
    """Verify the 6-digit code and set a new password."""
    error_msg = "Invalid or expired reset code."
    user = db.query(User).filter(User.email == body.email).first()
    if not user or not user.reset_code or not user.reset_code_expires_at:
        raise HTTPException(status_code=400, detail=error_msg)

    # Check expiry
    if user.reset_code_expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail=error_msg)

    # Verify code
    if not verify_password(body.code, user.reset_code):
        raise HTTPException(status_code=400, detail=error_msg)

    # Update password and clear reset fields
    user.hashed_password = hash_password(body.new_password)
    user.reset_code = None
    user.reset_code_expires_at = None
    db.commit()

    return MessageResponse(message="Password has been reset successfully.")


@router.post("/google", response_model=TokenResponse)
async def google_sign_in(body: GoogleSignInRequest, db: Session = Depends(get_db)):
    """Verify a Google ID token and sign in (or create) the user."""
    if not _GOOGLE_CLIENT_IDS:
        raise HTTPException(
            status_code=503,
            detail="Google sign-in is not configured.",
        )

    try:
        # Verify the token against all configured client IDs
        id_info = None
        for client_id in _GOOGLE_CLIENT_IDS:
            try:
                id_info = google_id_token.verify_oauth2_token(
                    body.id_token,
                    google_requests.Request(),
                    audience=client_id,
                )
                break
            except ValueError:
                continue

        if id_info is None:
            raise HTTPException(status_code=401, detail="Invalid Google token.")

    except Exception as e:
        logger.warning("Google token verification failed: %s", e)
        raise HTTPException(status_code=401, detail="Invalid Google token.")

    email = id_info.get("email")
    if not email:
        raise HTTPException(status_code=400, detail="Google account has no email.")

    # Find or create user
    user = db.query(User).filter(User.email == email).first()
    is_new = user is None

    if is_new:
        now = datetime.now(timezone.utc)
        user = User(
            email=email,
            hashed_password=hash_password(secrets.token_hex(32)),  # random pw for social users
            subscription_tier=SubscriptionTier.pro,
            trial_start_date=now,
            trial_end_date=now + timedelta(days=TRIAL_DAYS),
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    token = create_access_token(user.id)
    return TokenResponse(access_token=token)
