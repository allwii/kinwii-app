import enum
import uuid

from sqlalchemy import Boolean, Column, Date, DateTime, Enum, ForeignKey, String, Text, Time, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.database import Base


class EnergyType(str, enum.Enum):
    deep = "deep"
    admin = "admin"
    creative = "creative"
    personal = "personal"


class Task(Base):
    __tablename__ = "tasks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    weekly_plan_id = Column(
        UUID(as_uuid=True),
        ForeignKey("weekly_plans.id", ondelete="CASCADE"),
        nullable=False,
    )
    quarter_id = Column(
        UUID(as_uuid=True),
        ForeignKey("quarterly_goals.id", ondelete="SET NULL"),
        nullable=True,
    )
    title = Column(String(300), nullable=False)
    date = Column(Date, nullable=False)
    completed = Column(Boolean, default=False)
    energy_type = Column(Enum(EnergyType), default=EnergyType.deep)
    description = Column(Text, nullable=True)
    start_time = Column(Time, nullable=True)
    end_time = Column(Time, nullable=True)
    skip_reason = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="tasks")
    weekly_plan = relationship("WeeklyPlan", back_populates="tasks")
