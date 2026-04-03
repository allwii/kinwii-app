import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.middleware.subscription_middleware import require_pro
from app.models.coach_message import CoachMessage
from app.models.user import User
from app.schemas.coach import CoachMessageResponse, CoachMessageSend, CoachReply
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
