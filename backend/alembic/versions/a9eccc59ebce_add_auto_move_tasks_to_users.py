"""add_auto_move_tasks_to_users

Revision ID: a9eccc59ebce
Revises: 0a4b7eb2d96d
Create Date: 2026-04-15 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a9eccc59ebce'
down_revision: Union[str, None] = '0a4b7eb2d96d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'users',
        sa.Column('auto_move_tasks', sa.Boolean(), nullable=False, server_default=sa.text('true')),
    )


def downgrade() -> None:
    op.drop_column('users', 'auto_move_tasks')
