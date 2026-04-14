from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.middleware.subscription_middleware import get_user_tier, require_active_access
from app.models.goal import QuarterlyGoal
from app.models.user import User
from app.schemas.goal import GoalCreate, GoalResponse, GoalUpdate

FREE_GOAL_LIMIT = 1

router = APIRouter(prefix="/goals", tags=["goals"])


def _goal_to_response(goal: QuarterlyGoal) -> dict:
    """Convert a goal ORM object to a response dict with role_name."""
    data = {c.name: getattr(goal, c.name) for c in goal.__table__.columns}
    data["role_name"] = goal.role.name if goal.role else None
    return data


@router.get("", response_model=list[GoalResponse])
async def list_goals(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    goals = (
        db.query(QuarterlyGoal)
        .options(joinedload(QuarterlyGoal.role))
        .filter(QuarterlyGoal.user_id == current_user.id)
        .order_by(QuarterlyGoal.created_at.desc())
        .all()
    )
    return [_goal_to_response(g) for g in goals]


@router.post("", response_model=GoalResponse, status_code=201)
async def create_goal(
    body: GoalCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
    tier: str = Depends(get_user_tier),
):
    if tier != "pro":
        existing_count = (
            db.query(QuarterlyGoal)
            .filter(QuarterlyGoal.user_id == current_user.id)
            .count()
        )
        if existing_count >= FREE_GOAL_LIMIT:
            raise HTTPException(
                status_code=403,
                detail="Free plan is limited to 1 goal. Upgrade to Pro for unlimited goals.",
            )
    goal = QuarterlyGoal(user_id=current_user.id, **body.model_dump())
    db.add(goal)
    db.commit()
    db.refresh(goal)
    return _goal_to_response(goal)


@router.get("/{goal_id}", response_model=GoalResponse)
async def get_goal(
    goal_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    goal = (
        db.query(QuarterlyGoal)
        .options(joinedload(QuarterlyGoal.role))
        .filter(QuarterlyGoal.id == goal_id, QuarterlyGoal.user_id == current_user.id)
        .first()
    )
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
    return _goal_to_response(goal)


@router.put("/{goal_id}", response_model=GoalResponse)
async def update_goal(
    goal_id: UUID,
    body: GoalUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
):
    goal = (
        db.query(QuarterlyGoal)
        .options(joinedload(QuarterlyGoal.role))
        .filter(QuarterlyGoal.id == goal_id, QuarterlyGoal.user_id == current_user.id)
        .first()
    )
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(goal, key, value)
    db.commit()
    db.refresh(goal)
    return _goal_to_response(goal)


@router.delete("/{goal_id}", status_code=204)
async def delete_goal(
    goal_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
):
    goal = (
        db.query(QuarterlyGoal)
        .filter(QuarterlyGoal.id == goal_id, QuarterlyGoal.user_id == current_user.id)
        .first()
    )
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
    db.delete(goal)
    db.commit()
