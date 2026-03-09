import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.models.goal import QuarterlyGoal
from app.models.reflection import WeeklyReflection
from app.models.task import Task
from app.models.user import User
from app.models.weekly_plan import WeeklyPlan
from app.schemas.ai import (
    AlignWeekRequest,
    AlignWeekResponse,
    DailyFocusRequest,
    DailyFocusResponse,
    SuggestIntentRequest,
    SuggestIntentResponse,
    SummarizeReflectionRequest,
    SummarizeReflectionResponse,
)
from app.services.ai_service import AIService, get_ai_service

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post("/align-week", response_model=AlignWeekResponse)
async def align_week(
    body: AlignWeekRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    ai: AIService = Depends(get_ai_service),
):
    plan = (
        db.query(WeeklyPlan)
        .filter(
            WeeklyPlan.id == body.weekly_plan_id,
            WeeklyPlan.user_id == current_user.id,
        )
        .first()
    )
    if not plan:
        raise HTTPException(status_code=404, detail="Weekly plan not found")

    tasks = db.query(Task).filter(Task.weekly_plan_id == plan.id).all()

    try:
        suggestions = await ai.align_week(plan, tasks, db)
    except Exception as e:
        logger.exception("align_week failed: %s", e)
        raise HTTPException(
            status_code=503, detail=f"AI service error: {e}"
        )

    return AlignWeekResponse(suggestions=suggestions)


@router.post("/summarize-reflection", response_model=SummarizeReflectionResponse)
async def summarize_reflection(
    body: SummarizeReflectionRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    ai: AIService = Depends(get_ai_service),
):
    reflection = (
        db.query(WeeklyReflection)
        .filter(
            WeeklyReflection.id == body.reflection_id,
            WeeklyReflection.user_id == current_user.id,
        )
        .first()
    )
    if not reflection:
        raise HTTPException(status_code=404, detail="Reflection not found")

    try:
        summary, recommendation, pattern_insight = await ai.summarize_reflection(
            reflection, db
        )
    except Exception:
        raise HTTPException(
            status_code=503, detail="AI service temporarily unavailable"
        )

    reflection.ai_summary = summary
    reflection.ai_focus_recommendation = recommendation
    reflection.ai_pattern_insight = pattern_insight
    db.commit()

    return SummarizeReflectionResponse(
        summary=summary,
        focus_recommendation=recommendation,
        pattern_insight=pattern_insight,
    )


@router.post("/suggest-daily-focus", response_model=DailyFocusResponse)
async def suggest_daily_focus(
    body: DailyFocusRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    ai: AIService = Depends(get_ai_service),
):
    plan = (
        db.query(WeeklyPlan)
        .filter(
            WeeklyPlan.id == body.weekly_plan_id,
            WeeklyPlan.user_id == current_user.id,
        )
        .first()
    )
    if not plan:
        raise HTTPException(status_code=404, detail="Weekly plan not found")

    tasks = db.query(Task).filter(Task.weekly_plan_id == plan.id).all()

    try:
        suggestions, nudge = await ai.suggest_daily_focus(
            plan, tasks, body.date, db
        )
    except Exception:
        raise HTTPException(
            status_code=503, detail="AI service temporarily unavailable"
        )

    return DailyFocusResponse(suggestions=suggestions, nudge=nudge)


@router.post("/suggest-intent", response_model=SuggestIntentResponse)
async def suggest_intent(
    body: SuggestIntentRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    ai: AIService = Depends(get_ai_service),
):
    goal = (
        db.query(QuarterlyGoal)
        .filter(
            QuarterlyGoal.id == body.goal_id,
            QuarterlyGoal.user_id == current_user.id,
        )
        .first()
    )
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")

    previous_plan = None
    if body.previous_plan_id:
        previous_plan = (
            db.query(WeeklyPlan)
            .filter(
                WeeklyPlan.id == body.previous_plan_id,
                WeeklyPlan.user_id == current_user.id,
            )
            .first()
        )

    try:
        suggested_intent = await ai.suggest_intent(goal, previous_plan)
    except Exception:
        raise HTTPException(
            status_code=503, detail="AI service temporarily unavailable"
        )

    return SuggestIntentResponse(suggested_intent=suggested_intent)
