import uuid

from sqlalchemy import Column, DateTime, ForeignKey, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.database import Base


class WeeklyReflection(Base):
    __tablename__ = "weekly_reflections"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    weekly_plan_id = Column(
        UUID(as_uuid=True),
        ForeignKey("weekly_plans.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    moved_needle = Column(Text)
    drained_energy = Column(Text)
    stop_doing = Column(Text)
    focus_next_week = Column(Text)
    ai_summary = Column(Text)
    ai_focus_recommendation = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="reflections")
    weekly_plan = relationship("WeeklyPlan", back_populates="reflection")
