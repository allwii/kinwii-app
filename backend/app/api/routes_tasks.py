from datetime import date, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.middleware.subscription_middleware import require_active_access
from app.models.task import Task
from app.models.user import User
from app.models.weekly_plan import WeeklyPlan
from app.schemas.task import CarryForwardRequest, TaskCreate, TaskResponse, TaskUpdate
from app.services.alignment_service import update_week_progress

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", response_model=list[TaskResponse])
async def list_tasks(
    date: date | None = Query(None),
    start_date: date | None = Query(None),
    end_date: date | None = Query(None),
    weekly_plan_id: UUID | None = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    has_range = start_date is not None and end_date is not None
    if not date and not weekly_plan_id and not has_range:
        raise HTTPException(
            status_code=400,
            detail=(
                "Provide 'date', 'weekly_plan_id', "
                "or both 'start_date' and 'end_date'"
            ),
        )
    query = db.query(Task).filter(Task.user_id == current_user.id)
    if weekly_plan_id:
        query = query.filter(Task.weekly_plan_id == weekly_plan_id)
    if date:
        query = query.filter(Task.date == date)
    if start_date:
        query = query.filter(Task.date >= start_date)
    if end_date:
        query = query.filter(Task.date <= end_date)
    return query.order_by(Task.created_at).all()


@router.post("", response_model=TaskResponse, status_code=201)
async def create_task(
    body: TaskCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
):
    task = Task(user_id=current_user.id, **body.model_dump())
    db.add(task)
    db.commit()
    db.refresh(task)
    update_week_progress(task.weekly_plan_id, db)
    db.commit()
    return task


@router.put("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: UUID,
    body: TaskUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
):
    task = (
        db.query(Task)
        .filter(Task.id == task_id, Task.user_id == current_user.id)
        .first()
    )
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(task, key, value)
    db.commit()
    db.refresh(task)
    return task


@router.patch("/{task_id}/complete", response_model=TaskResponse)
async def toggle_task_complete(
    task_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
):
    task = (
        db.query(Task)
        .filter(Task.id == task_id, Task.user_id == current_user.id)
        .first()
    )
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    task.completed = not task.completed
    db.commit()
    db.refresh(task)
    update_week_progress(task.weekly_plan_id, db)
    db.commit()
    return task


@router.delete("/{task_id}", status_code=204)
async def delete_task(
    task_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
):
    task = (
        db.query(Task)
        .filter(Task.id == task_id, Task.user_id == current_user.id)
        .first()
    )
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    weekly_plan_id = task.weekly_plan_id
    db.delete(task)
    db.commit()
    update_week_progress(weekly_plan_id, db)
    db.commit()


@router.post("/carry-forward", response_model=list[TaskResponse], status_code=201)
async def carry_forward_tasks(
    body: CarryForwardRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_access),
):
    # Verify target plan belongs to user
    target_plan = (
        db.query(WeeklyPlan)
        .filter(
            WeeklyPlan.id == body.target_weekly_plan_id,
            WeeklyPlan.user_id == current_user.id,
        )
        .first()
    )
    if not target_plan:
        raise HTTPException(status_code=404, detail="Target weekly plan not found")

    # Fetch source tasks owned by user
    source_tasks = (
        db.query(Task)
        .filter(Task.id.in_(body.task_ids), Task.user_id == current_user.id)
        .all()
    )
    if not source_tasks:
        raise HTTPException(status_code=404, detail="No matching tasks found")

    new_tasks = []
    for t in source_tasks:
        new_task = Task(
            user_id=current_user.id,
            weekly_plan_id=body.target_weekly_plan_id,
            title=t.title,
            date=body.target_date,
            energy_type=t.energy_type,
            completed=False,
        )
        db.add(new_task)
        new_tasks.append(new_task)

    db.commit()
    for nt in new_tasks:
        db.refresh(nt)
    update_week_progress(body.target_weekly_plan_id, db)
    db.commit()
    return new_tasks


@router.post("/auto-move", response_model=list[TaskResponse])
async def auto_move_tasks(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Move yesterday's unfinished tasks to today.

    Called by the mobile app on launch when the user has auto_move_tasks
    enabled. Only moves tasks that are incomplete and have no skip_reason
    (skipped tasks are intentionally left behind). Idempotent — safe to
    call multiple times per day since it only looks at yesterday's tasks.
    """
    if not current_user.auto_move_tasks:
        return []

    today = date.today()
    yesterday = today - timedelta(days=1)

    unfinished = (
        db.query(Task)
        .filter(
            Task.user_id == current_user.id,
            Task.date == yesterday,
            Task.completed.is_(False),
            Task.skip_reason.is_(None),
        )
        .all()
    )

    if not unfinished:
        return []

    # If the move crosses a week boundary (e.g., Sun → Mon), the task's
    # weekly_plan_id no longer matches the new week and the Week screen would
    # not find it. Resolve the correct plan for the new date once and re-link.
    def _monday_of(d: date) -> date:
        return d - timedelta(days=d.weekday())

    crossed_week = _monday_of(yesterday) != _monday_of(today)
    new_plan_id = None
    if crossed_week:
        new_plan = (
            db.query(WeeklyPlan)
            .filter(
                WeeklyPlan.user_id == current_user.id,
                WeeklyPlan.week_start_date == _monday_of(today),
            )
            .first()
        )
        if new_plan is not None:
            new_plan_id = new_plan.id

    for task in unfinished:
        task.date = today
        if new_plan_id is not None:
            task.weekly_plan_id = new_plan_id
    db.commit()

    for task in unfinished:
        db.refresh(task)

    return unfinished
