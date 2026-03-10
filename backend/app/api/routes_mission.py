from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.middleware.auth_middleware import get_current_user
from app.models.mission import Mission
from app.models.role import Role
from app.models.user import User
from app.schemas.mission import (
    MissionResponse,
    MissionUpdate,
    RoleCreate,
    RoleResponse,
    RoleUpdate,
)

router = APIRouter(prefix="/mission", tags=["mission"])


# ── Mission ──────────────────────────────────────────────────────────────


@router.get("", response_model=MissionResponse | None)
async def get_mission(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(Mission).filter(Mission.user_id == current_user.id).first()
    )


@router.put("", response_model=MissionResponse)
async def upsert_mission(
    body: MissionUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    mission = (
        db.query(Mission).filter(Mission.user_id == current_user.id).first()
    )
    if mission:
        mission.statement = body.statement
    else:
        mission = Mission(user_id=current_user.id, statement=body.statement)
        db.add(mission)
    db.commit()
    db.refresh(mission)
    return mission


# ── Roles ────────────────────────────────────────────────────────────────


@router.get("/roles", response_model=list[RoleResponse])
async def list_roles(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(Role)
        .filter(Role.user_id == current_user.id)
        .order_by(Role.created_at)
        .all()
    )


@router.post("/roles", response_model=RoleResponse, status_code=201)
async def create_role(
    body: RoleCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    role = Role(user_id=current_user.id, **body.model_dump())
    db.add(role)
    db.commit()
    db.refresh(role)
    return role


@router.put("/roles/{role_id}", response_model=RoleResponse)
async def update_role(
    role_id: UUID,
    body: RoleUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    role = (
        db.query(Role)
        .filter(Role.id == role_id, Role.user_id == current_user.id)
        .first()
    )
    if not role:
        raise HTTPException(status_code=404, detail="Role not found")
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(role, key, value)
    db.commit()
    db.refresh(role)
    return role


@router.delete("/roles/{role_id}", status_code=204)
async def delete_role(
    role_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    role = (
        db.query(Role)
        .filter(Role.id == role_id, Role.user_id == current_user.id)
        .first()
    )
    if not role:
        raise HTTPException(status_code=404, detail="Role not found")
    db.delete(role)
    db.commit()
