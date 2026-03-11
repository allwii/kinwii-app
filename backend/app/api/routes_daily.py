import datetime as dt
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.models.daily_intent import DailyIntent
from app.models.user import User
from app.schemas.daily_intent import (
    DailyIntentCreate,
    DailyIntentResponse,
    DailyIntentUpdate,
)

router = APIRouter(prefix="/daily", tags=["daily"])


@router.get("", response_model=DailyIntentResponse | None)
async def get_daily_intent(
    date: dt.date = Query(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(DailyIntent)
        .filter(
            DailyIntent.user_id == current_user.id,
            DailyIntent.date == date,
        )
        .first()
    )


@router.post("", response_model=DailyIntentResponse, status_code=201)
async def create_daily_intent(
    body: DailyIntentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Check if one already exists for this date
    existing = (
        db.query(DailyIntent)
        .filter(
            DailyIntent.user_id == current_user.id,
            DailyIntent.date == body.date,
        )
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=409,
            detail="Daily intent already exists for this date. Use PUT to update.",
        )

    intent = DailyIntent(user_id=current_user.id, **body.model_dump())
    db.add(intent)
    db.commit()
    db.refresh(intent)
    return intent


@router.put("/{intent_id}", response_model=DailyIntentResponse)
async def update_daily_intent(
    intent_id: UUID,
    body: DailyIntentUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    intent = (
        db.query(DailyIntent)
        .filter(
            DailyIntent.id == intent_id,
            DailyIntent.user_id == current_user.id,
        )
        .first()
    )
    if not intent:
        raise HTTPException(status_code=404, detail="Daily intent not found")
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(intent, key, value)
    db.commit()
    db.refresh(intent)
    return intent
