from uuid import UUID

from fastapi import APIRouter, Depends

from app import db
from app.repositories import rounds
from app.schemas.round import CancelRound, RoundView
from app.security.auth import CurrentUser
from app.security.roles import StaffRole, require_role
from app.services.db_errors import business_errors

router = APIRouter(prefix="/v1/admin", tags=["administration"])

admin = require_role(StaffRole.ADMIN, StaffRole.SUPER_ADMIN)


@router.post("/engine/tick")
async def engine_tick(staff: CurrentUser = Depends(admin)) -> dict:
    """Fait avancer le moteur immédiatement (normalement automatique chaque minute)."""
    async with db.transaction(actor_id=staff.id) as conn:
        return await rounds.engine_tick(conn)


@router.post("/rounds/{round_id}/cancel", response_model=RoundView)
async def cancel_round(round_id: UUID, body: CancelRound, staff: CurrentUser = Depends(admin)) -> RoundView:
    async with db.transaction(actor_id=staff.id) as conn:
        with business_errors():
            await rounds.cancel(conn, round_id, staff.id, body.reason)
        return RoundView(**await rounds.get(conn, round_id))
