import uuid

from sqlalchemy import Boolean, Column, Date, DateTime, ForeignKey, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.database import Base


class DailyIntent(Base):
    __tablename__ = "daily_intents"
    __table_args__ = (
        UniqueConstraint("user_id", "date", name="uq_user_daily_intent"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    weekly_plan_id = Column(
        UUID(as_uuid=True),
        ForeignKey("weekly_plans.id", ondelete="SET NULL"),
        nullable=True,
    )
    date = Column(Date, nullable=False)
    intent = Column(Text, nullable=False)
    honored = Column(Boolean, nullable=True)
    note = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="daily_intents")
    weekly_plan = relationship("WeeklyPlan")
