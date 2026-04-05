"""Analytics endpoints — progress trends, energy breakdown, weekly rhythm."""

from datetime import date, timedelta

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.models.goal import QuarterlyGoal
from app.models.reflection import WeeklyReflection
from app.models.task import EnergyType, Task
from app.models.user import User
from app.models.weekly_plan import WeeklyPlan

router = APIRouter(prefix="/analytics", tags=["analytics"])


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class WeekCompletion(BaseModel):
    week_start: date
    total_tasks: int
    completed_tasks: int
    completion_rate: float


class EnergyBreakdown(BaseModel):
    energy_type: str
    count: int


class RhythmWeek(BaseModel):
    week_start: date
    had_intent: bool
    had_task_done: bool
    had_reflection: bool
    is_rhythm_week: bool


class GoalProgress(BaseModel):
    goal_id: str
    title: str
    progress_percent: int
    weeks_remaining: int


class AnalyticsResponse(BaseModel):
    weekly_completions: list[WeekCompletion]
    energy_breakdown: list[EnergyBreakdown]
    rhythm_weeks: list[RhythmWeek]
    goal_progress: list[GoalProgress]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _monday_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------


@router.get("/progress", response_model=AnalyticsResponse)
async def get_progress(
    weeks: int = 8,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uid = current_user.id
    today = date.today()
    start_monday = _monday_of(today) - timedelta(weeks=weeks - 1)

    # --- Weekly task completions (last N weeks) ---
    tasks = (
        db.query(Task)
        .filter(Task.user_id == uid, Task.date >= start_monday)
        .all()
    )

    week_buckets: dict[date, list[Task]] = {}
    for t in tasks:
        m = _monday_of(t.date)
        week_buckets.setdefault(m, []).append(t)

    weekly_completions = []
    for i in range(weeks):
        w = start_monday + timedelta(weeks=i)
        bucket = week_buckets.get(w, [])
        total = len(bucket)
        done = sum(1 for t in bucket if t.completed)
        weekly_completions.append(
            WeekCompletion(
                week_start=w,
                total_tasks=total,
                completed_tasks=done,
                completion_rate=round(done / total, 2) if total > 0 else 0.0,
            )
        )

    # --- Energy type breakdown (all time) ---
    energy_rows = (
        db.query(Task.energy_type, func.count())
        .filter(Task.user_id == uid, Task.completed.is_(True))
        .group_by(Task.energy_type)
        .all()
    )
    energy_breakdown = [
        EnergyBreakdown(
            energy_type=row[0].value if row[0] else "deep",
            count=row[1],
        )
        for row in energy_rows
    ]

    # --- Weekly rhythm (last N weeks) ---
    plans = (
        db.query(WeeklyPlan)
        .filter(WeeklyPlan.user_id == uid, WeeklyPlan.week_start_date >= start_monday)
        .all()
    )
    plan_by_week = {p.week_start_date: p for p in plans}

    reflections = (
        db.query(WeeklyReflection)
        .filter(WeeklyReflection.user_id == uid)
        .join(WeeklyPlan, WeeklyReflection.weekly_plan_id == WeeklyPlan.id)
        .filter(WeeklyPlan.week_start_date >= start_monday)
        .all()
    )
    reflected_plan_ids = {r.weekly_plan_id for r in reflections}

    rhythm_weeks = []
    for i in range(weeks):
        w = start_monday + timedelta(weeks=i)
        plan = plan_by_week.get(w)
        had_intent = plan is not None
        had_task_done = False
        had_reflection = False
        if plan:
            bucket = week_buckets.get(w, [])
            had_task_done = any(t.completed for t in bucket)
            had_reflection = plan.id in reflected_plan_ids
        rhythm_weeks.append(
            RhythmWeek(
                week_start=w,
                had_intent=had_intent,
                had_task_done=had_task_done,
                had_reflection=had_reflection,
                is_rhythm_week=had_intent and had_task_done and had_reflection,
            )
        )

    # --- Goal progress ---
    goals = (
        db.query(QuarterlyGoal)
        .filter(QuarterlyGoal.user_id == uid)
        .order_by(QuarterlyGoal.created_at.desc())
        .all()
    )
    goal_progress = [
        GoalProgress(
            goal_id=str(g.id),
            title=g.title,
            progress_percent=g.progress_percent or 0,
            weeks_remaining=max(0, (g.end_date - today).days // 7),
        )
        for g in goals
    ]

    return AnalyticsResponse(
        weekly_completions=weekly_completions,
        energy_breakdown=energy_breakdown,
        rhythm_weeks=rhythm_weeks,
        goal_progress=goal_progress,
    )
