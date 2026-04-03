import enum
import uuid

from sqlalchemy import Column, DateTime, Enum, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.database import Base


class SubscriptionTier(str, enum.Enum):
    free = "free"
    pro = "pro"


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String, unique=True, nullable=False, index=True)
    hashed_password = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Subscription fields
    subscription_tier = Column(
        Enum(SubscriptionTier), nullable=False, server_default="free"
    )
    trial_start_date = Column(DateTime(timezone=True), nullable=True)
    trial_end_date = Column(DateTime(timezone=True), nullable=True)
    subscription_expires_at = Column(DateTime(timezone=True), nullable=True)
    revenuecat_id = Column(String, nullable=True)

    mission = relationship("Mission", back_populates="user", uselist=False, cascade="all, delete-orphan")
    roles = relationship("Role", back_populates="user", cascade="all, delete-orphan")
    goals = relationship("QuarterlyGoal", back_populates="user", cascade="all, delete-orphan")
    weekly_plans = relationship("WeeklyPlan", back_populates="user", cascade="all, delete-orphan")
    tasks = relationship("Task", back_populates="user", cascade="all, delete-orphan")
    reflections = relationship("WeeklyReflection", back_populates="user", cascade="all, delete-orphan")
    daily_intents = relationship("DailyIntent", back_populates="user", cascade="all, delete-orphan")
    coach_messages = relationship("CoachMessage", back_populates="user", cascade="all, delete-orphan")
