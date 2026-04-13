"""add_coach_briefings

Introduces a once-per-day AI coaching briefing, cached by (user_id, date) so
the same briefing is shown all day without triggering repeated LLM calls.

Revision ID: 0a4b7eb2d96d
Revises: 7b651102f0a5
Create Date: 2026-04-13 13:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '0a4b7eb2d96d'
down_revision: Union[str, None] = '7b651102f0a5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'coach_briefings',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'user_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('users.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('date', sa.Date(), nullable=False),
        sa.Column('headline', sa.String(length=200), nullable=False),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column(
            'followups',
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=True,
        ),
        sa.UniqueConstraint('user_id', 'date', name='coach_briefings_user_date_uq'),
    )
    op.create_index(
        'ix_coach_briefings_user_id',
        'coach_briefings',
        ['user_id'],
    )


def downgrade() -> None:
    op.drop_index('ix_coach_briefings_user_id', table_name='coach_briefings')
    op.drop_table('coach_briefings')
