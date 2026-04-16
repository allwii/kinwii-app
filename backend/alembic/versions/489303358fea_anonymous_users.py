"""anonymous_users

Make email/password nullable, add device_id and is_anonymous columns
to support anonymous device-based accounts.

Revision ID: 489303358fea
Revises: a9eccc59ebce
Create Date: 2026-04-16 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '489303358fea'
down_revision: Union[str, None] = 'a9eccc59ebce'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Make email nullable and replace unique index with partial index
    op.alter_column('users', 'email', existing_type=sa.String(), nullable=True)
    op.drop_index('ix_users_email', table_name='users')
    op.execute(
        "CREATE UNIQUE INDEX ix_users_email_not_null ON users(email) WHERE email IS NOT NULL"
    )

    # Make password nullable
    op.alter_column('users', 'hashed_password', existing_type=sa.String(), nullable=True)

    # Add device_id and is_anonymous
    op.add_column('users', sa.Column('device_id', sa.String(), nullable=True))
    op.create_index('ix_users_device_id', 'users', ['device_id'], unique=True)
    op.add_column(
        'users',
        sa.Column('is_anonymous', sa.Boolean(), nullable=False, server_default=sa.text('true')),
    )

    # Backfill: existing users with email are not anonymous
    op.execute("UPDATE users SET is_anonymous = false WHERE email IS NOT NULL")


def downgrade() -> None:
    op.drop_column('users', 'is_anonymous')
    op.drop_index('ix_users_device_id', table_name='users')
    op.drop_column('users', 'device_id')
    op.alter_column('users', 'hashed_password', existing_type=sa.String(), nullable=False)
    op.drop_index('ix_users_email_not_null', table_name='users')
    op.create_index('ix_users_email', 'users', ['email'], unique=True)
    op.alter_column('users', 'email', existing_type=sa.String(), nullable=False)
