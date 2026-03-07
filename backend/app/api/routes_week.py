from datetime import date, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.models.user import User
from app.models.weekly_plan import WeeklyPlan
from app.schemas.weekly_plan import WeeklyPlanCreate, WeeklyPlanResponse, WeeklyPlanUpdate

router = APIRouter(prefix="/week", tags=["week"])


def _current_monday() -> date:
    today = date.today()
    return today - timedelta(days=today.weekday())


@router.get("/current", response_model=WeeklyPlanResponse)
async def get_current_week(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    monday = _current_monday()
    plan = (
        db.query(WeeklyPlan)
        .filter(
            WeeklyPlan.user_id == current_user.id,
            WeeklyPlan.week_start_date == monday,
        )
        .first()
    )
    if not plan:
        raise HTTPException(status_code=404, detail="No plan for current week")
    return plan


@router.get("/previous", response_model=WeeklyPlanResponse)
async def get_previous_week(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    monday = _current_monday()
    plan = (
        db.query(WeeklyPlan)
        .filter(
            WeeklyPlan.user_id == current_user.id,
            WeeklyPlan.week_start_date < monday,
        )
        .order_by(WeeklyPlan.week_start_date.desc())
        .first()
    )
    if not plan:
        raise HTTPException(status_code=404, detail="No previous week plan found")
    return plan


@router.post("", response_model=WeeklyPlanResponse, status_code=201)
async def create_week_plan(
    body: WeeklyPlanCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    existing = (
        db.query(WeeklyPlan)
        .filter(
            WeeklyPlan.user_id == current_user.id,
            WeeklyPlan.week_start_date == body.week_start_date,
        )
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=409, detail="Plan already exists for this week"
        )
    plan = WeeklyPlan(user_id=current_user.id, **body.model_dump())
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan


@router.get("/{plan_id}", response_model=WeeklyPlanResponse)
async def get_week_plan(
    plan_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    plan = (
        db.query(WeeklyPlan)
        .filter(WeeklyPlan.id == plan_id, WeeklyPlan.user_id == current_user.id)
        .first()
    )
    if not plan:
        raise HTTPException(status_code=404, detail="Weekly plan not found")
    return plan


@router.put("/{plan_id}", response_model=WeeklyPlanResponse)
async def update_week_plan(
    plan_id: UUID,
    body: WeeklyPlanUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    plan = (
        db.query(WeeklyPlan)
        .filter(WeeklyPlan.id == plan_id, WeeklyPlan.user_id == current_user.id)
        .first()
    )
    if not plan:
        raise HTTPException(status_code=404, detail="Weekly plan not found")
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(plan, key, value)
    db.commit()
    db.refresh(plan)
    return plan
