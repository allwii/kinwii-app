from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.models.task import Task
from app.models.user import User
from app.models.weekly_plan import WeeklyPlan
from app.schemas.task import CarryForwardRequest, TaskCreate, TaskResponse, TaskUpdate
from app.services.alignment_service import update_week_progress

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", response_model=list[TaskResponse])
async def list_tasks(
    date: date | None = Query(None),
    weekly_plan_id: UUID | None = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not date and not weekly_plan_id:
        raise HTTPException(
            status_code=400,
            detail="Provide either 'date' or 'weekly_plan_id' query parameter",
        )
    query = db.query(Task).filter(Task.user_id == current_user.id)
    if weekly_plan_id:
        query = query.filter(Task.weekly_plan_id == weekly_plan_id)
    if date:
        query = query.filter(Task.date == date)
    return query.order_by(Task.created_at).all()


@router.post("", response_model=TaskResponse, status_code=201)
async def create_task(
    body: TaskCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
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
