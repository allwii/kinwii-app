import logging
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.middleware.subscription_middleware import _is_pro, require_pro
from app.models.coach_briefing import CoachBriefing
from app.models.coach_message import CoachMessage
from app.models.user import User
from app.schemas.coach import CoachMessageResponse, CoachMessageSend, CoachReply
from app.schemas.coach_briefing import CoachBriefingResponse
from app.services.ai_service import AIService, get_ai_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/coach", tags=["coach"])


@router.get("/messages", response_model=list[CoachMessageResponse])
async def list_messages(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    messages = (
        db.query(CoachMessage)
        .filter(CoachMessage.user_id == current_user.id)
        .order_by(CoachMessage.created_at.desc())
        .limit(20)
        .all()
    )
    # Return in chronological order
    return list(reversed(messages))


@router.post("/message", response_model=CoachReply)
async def send_message(
    body: CoachMessageSend,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_pro),
    ai: AIService = Depends(get_ai_service),
):
    # Store user message
    user_msg = CoachMessage(
        user_id=current_user.id,
        role="user",
        content=body.content,
    )
    db.add(user_msg)
    db.commit()
    db.refresh(user_msg)

    # Fetch recent history for context
    history = (
        db.query(CoachMessage)
        .filter(CoachMessage.user_id == current_user.id)
        .order_by(CoachMessage.created_at.desc())
        .limit(20)
        .all()
    )
    history = list(reversed(history))

    try:
        reply_content = await ai.coach_respond(current_user, history, db)
    except Exception as e:
        logger.exception("coach_respond failed: %s", e)
        raise HTTPException(
            status_code=503, detail="AI service temporarily unavailable"
        )

    # Store assistant message
    assistant_msg = CoachMessage(
        user_id=current_user.id,
        role="assistant",
        content=reply_content,
    )
    db.add(assistant_msg)
    db.commit()
    db.refresh(assistant_msg)

    return CoachReply(user_message=user_msg, assistant_message=assistant_msg)


@router.get("/briefing", response_model=CoachBriefingResponse)
async def get_daily_briefing(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    ai: AIService = Depends(get_ai_service),
):
    """Return today's coaching briefing for the current user.

    Generates + caches a new briefing the first time this is called each
    calendar day. Free-tier users get the same headline but body/followups are
    stripped so the client can render a paywall teaser.
    """
    today = date.today()
    is_pro = _is_pro(current_user)

    briefing = (
        db.query(CoachBriefing)
        .filter(
            CoachBriefing.user_id == current_user.id,
            CoachBriefing.date == today,
        )
        .first()
    )

    if briefing is None:
        try:
            payload = await ai.generate_coach_briefing(current_user, db)
        except Exception as e:
            logger.exception("generate_coach_briefing failed: %s", e)
            raise HTTPException(
                status_code=503, detail="AI service temporarily unavailable"
            )

        briefing = CoachBriefing(
            user_id=current_user.id,
            date=today,
            headline=payload["headline"],
            body=payload["body"],
            followups=payload["followups"],
        )
        db.add(briefing)
        try:
            db.commit()
            db.refresh(briefing)
        except IntegrityError:
            # Another request created it concurrently; fetch the winner.
            db.rollback()
            briefing = (
                db.query(CoachBriefing)
                .filter(
                    CoachBriefing.user_id == current_user.id,
                    CoachBriefing.date == today,
                )
                .first()
            )
            if briefing is None:
                raise HTTPException(status_code=500, detail="Briefing race lost")

    return CoachBriefingResponse(
        id=briefing.id,
        date=briefing.date,
        headline=briefing.headline,
        body=briefing.body if is_pro else None,
        followups=list(briefing.followups) if is_pro else [],
        is_pro=is_pro,
        created_at=briefing.created_at,
    )
