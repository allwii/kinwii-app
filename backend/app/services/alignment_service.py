from uuid import UUID

from sqlalchemy.orm import Session

from app.models.task import Task
from app.models.weekly_plan import WeeklyPlan


def calculate_week_progress(weekly_plan_id: UUID, db: Session) -> int:
    tasks = db.query(Task).filter(Task.weekly_plan_id == weekly_plan_id).all()
    if not tasks:
        return 0
    completed = sum(1 for t in tasks if t.completed)
    return round((completed / len(tasks)) * 100)


def update_week_progress(weekly_plan_id: UUID, db: Session) -> None:
    progress = calculate_week_progress(weekly_plan_id, db)
    db.query(WeeklyPlan).filter(WeeklyPlan.id == weekly_plan_id).update(
        {"progress_percent": progress}
    )
