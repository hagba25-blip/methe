from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Query

from app import db
from app.repositories import withdrawals
from app.schemas.withdrawal import AdminWithdrawalView, ProcessWithdrawal, WithdrawalStatus, WithdrawalView
from app.security.auth import CurrentUser
from app.security.roles import StaffRole, require_role
from app.services.db_errors import business_errors

router = APIRouter(prefix="/v1/admin", tags=["administration"])

finance = require_role(StaffRole.FINANCE, StaffRole.ADMIN, StaffRole.SUPER_ADMIN)


@router.get("/withdrawals", response_model=list[AdminWithdrawalView])
async def list_withdrawals(
    status: WithdrawalStatus | None = "pending",
    limit: int = Query(default=50, ge=1, le=200),
    staff: CurrentUser = Depends(require_role()),
) -> list[AdminWithdrawalView]:
    async with db.transaction() as conn:
        return [AdminWithdrawalView(**w) for w in await withdrawals.list_for_admin(conn, status, limit)]


@router.post("/withdrawals/{withdrawal_id}/{action}", response_model=WithdrawalView)
async def process(
    withdrawal_id: UUID,
    action: Literal["review", "approve", "pay", "reject"],
    body: ProcessWithdrawal | None = None,
    staff: CurrentUser = Depends(finance),
) -> WithdrawalView:
    """review → EN VÉRIFICATION, approve → APPROUVÉ, pay → PAYÉ, reject (motif obligatoire) → REFUSÉ."""
    async with db.transaction(actor_id=staff.id) as conn:
        with business_errors():
            await withdrawals.process(conn, withdrawal_id, staff.id, action, body.reason if body else None)
        return WithdrawalView(**await withdrawals.get(conn, withdrawal_id))
