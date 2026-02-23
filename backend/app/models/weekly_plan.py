import uuid

from sqlalchemy import Column, Date, DateTime, ForeignKey, Integer, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.database import Base


class WeeklyPlan(Base):
    __tablename__ = "weekly_plans"
    __table_args__ = (
        UniqueConstraint("user_id", "week_start_date", name="uq_user_week"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    quarter_id = Column(
        UUID(as_uuid=True),
        ForeignKey("quarterly_goals.id", ondelete="SET NULL"),
        nullable=True,
    )
    week_start_date = Column(Date, nullable=False)
    intent = Column(Text, nullable=False)
    progress_percent = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="weekly_plans")
    quarterly_goal = relationship("QuarterlyGoal", back_populates="weekly_plans")
    tasks = relationship("Task", back_populates="weekly_plan", cascade="all, delete-orphan")
    reflection = relationship("WeeklyReflection", back_populates="weekly_plan", uselist=False)
