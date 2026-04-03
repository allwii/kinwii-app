"""add_subscription_fields_to_users

Revision ID: 061efd6aa36b
Revises: d5ae34c3ed6c
Create Date: 2026-04-02 21:48:06.464102

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '061efd6aa36b'
down_revision: Union[str, None] = 'd5ae34c3ed6c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    subscriptiontier = sa.Enum('free', 'pro', name='subscriptiontier')
    subscriptiontier.create(op.get_bind(), checkfirst=True)
    op.add_column('users', sa.Column('subscription_tier', subscriptiontier, server_default='free', nullable=False))
    op.add_column('users', sa.Column('trial_start_date', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('trial_end_date', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('subscription_expires_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('revenuecat_id', sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'revenuecat_id')
    op.drop_column('users', 'subscription_expires_at')
    op.drop_column('users', 'trial_end_date')
    op.drop_column('users', 'trial_start_date')
    op.drop_column('users', 'subscription_tier')
    sa.Enum(name='subscriptiontier').drop(op.get_bind(), checkfirst=True)
