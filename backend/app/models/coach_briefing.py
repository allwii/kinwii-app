import uuid

from sqlalchemy import Column, Date, DateTime, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import relationship

from app.database import Base


class CoachBriefing(Base):
    """A once-per-day AI-generated coaching briefing for a user.

    Generated lazily on first read each calendar day; cached in the DB so the
    same briefing is shown all day and not regenerated across app launches.
    """

    __tablename__ = "coach_briefings"
    __table_args__ = (
        UniqueConstraint("user_id", "date", name="coach_briefings_user_date_uq"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    date = Column(Date, nullable=False)
    headline = Column(String(200), nullable=False)
    body = Column(Text, nullable=False)
    followups = Column(JSONB, nullable=False, default=list)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="coach_briefings")
