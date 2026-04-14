from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.middleware.subscription_middleware import require_active_access
from app.models.reflection import WeeklyReflection
from app.models.user import User
from app.schemas.reflection import ReflectionCreate, ReflectionResponse, ReflectionUpdate

router = APIRouter(prefix="/reflection", tags=["reflection"])


@router.get("/{weekly_plan_id}", response_model=ReflectionResponse)
async def get_reflection(
    weekly_plan_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    reflection = (
        db.query(WeeklyReflection)
        .filter(
            WeeklyReflection.weekly_plan_id == weekly_plan_id,
            WeeklyReflection.user_id == current_user.id,
        )
        .first()
    )
    if not reflection:
        raise HTTPException(status_code=404, detail="Reflection not found")
    return reflection


@router.post("", response_model=ReflectionResponse, status_code=201)
async def create_reflection(
    body: ReflectionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
):
    existing = (
        db.query(WeeklyReflection)
        .filter(
            WeeklyReflection.weekly_plan_id == body.weekly_plan_id,
            WeeklyReflection.user_id == current_user.id,
        )
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=409, detail="Reflection already exists for this week"
        )
    reflection = WeeklyReflection(user_id=current_user.id, **body.model_dump())
    db.add(reflection)
    db.commit()
    db.refresh(reflection)
    return reflection


@router.put("/{reflection_id}", response_model=ReflectionResponse)
async def update_reflection(
    reflection_id: UUID,
    body: ReflectionUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
):
    reflection = (
        db.query(WeeklyReflection)
        .filter(
            WeeklyReflection.id == reflection_id,
            WeeklyReflection.user_id == current_user.id,
        )
        .first()
    )
    if not reflection:
        raise HTTPException(status_code=404, detail="Reflection not found")
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(reflection, key, value)
    db.commit()
    db.refresh(reflection)
    return reflection
