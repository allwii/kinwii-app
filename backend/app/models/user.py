import uuid

from sqlalchemy import Column, DateTime, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String, unique=True, nullable=False, index=True)
    hashed_password = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    mission = relationship("Mission", back_populates="user", uselist=False, cascade="all, delete-orphan")
    roles = relationship("Role", back_populates="user", cascade="all, delete-orphan")
    goals = relationship("QuarterlyGoal", back_populates="user", cascade="all, delete-orphan")
    weekly_plans = relationship("WeeklyPlan", back_populates="user", cascade="all, delete-orphan")
    tasks = relationship("Task", back_populates="user", cascade="all, delete-orphan")
    reflections = relationship("WeeklyReflection", back_populates="user", cascade="all, delete-orphan")
