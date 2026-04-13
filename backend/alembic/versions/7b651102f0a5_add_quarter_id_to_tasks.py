"""add_quarter_id_to_tasks

Adds a per-task quarterly goal foreign key so a task can be associated with
a specific goal independent of (or aligned with) its weekly plan's goal.
Existing rows are backfilled from their weekly_plan.quarter_id so the
current behavior — where each task inherits its plan's goal — is preserved.

Revision ID: 7b651102f0a5
Revises: 8db07f4d7e81
Create Date: 2026-04-13 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '7b651102f0a5'
down_revision: Union[str, None] = '8db07f4d7e81'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'tasks',
        sa.Column('quarter_id', postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        'tasks_quarter_id_fkey',
        'tasks',
        'quarterly_goals',
        ['quarter_id'],
        ['id'],
        ondelete='SET NULL',
    )
    # Backfill: inherit goal from the task's weekly plan.
    op.execute(
        """
        UPDATE tasks t
        SET quarter_id = wp.quarter_id
        FROM weekly_plans wp
        WHERE t.weekly_plan_id = wp.id
          AND wp.quarter_id IS NOT NULL
          AND t.quarter_id IS NULL
        """
    )


def downgrade() -> None:
    op.drop_constraint('tasks_quarter_id_fkey', 'tasks', type_='foreignkey')
    op.drop_column('tasks', 'quarter_id')
