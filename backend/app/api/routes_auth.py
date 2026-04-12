import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

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
    MessageResponse,
    ResetPasswordRequest,
    TokenResponse,
    UserCreate,
    UserResponse,
)
from app.services.email_service import send_reset_code_email

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
