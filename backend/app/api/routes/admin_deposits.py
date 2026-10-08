from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Path, Query

from app import db
from app.repositories import deposits
from app.schemas.deposit import AdminDepositView, ApproveDeposit, BalanceChange, CreditRequest, DepositView, RejectDeposit
from app.security.auth import CurrentUser
from app.security.roles import StaffRole, require_role
from app.services.db_errors import business_errors

router = APIRouter(prefix="/v1/admin", tags=["administration"])

# Seules les personnes habilitées aux finances touchent aux soldes.
finance = require_role(StaffRole.FINANCE, StaffRole.ADMIN, StaffRole.SUPER_ADMIN)


@router.get("/deposits", response_model=list[AdminDepositView])
async def list_deposits(
    status: Literal["pending", "approved", "rejected", "cancelled"] | None = "pending",
    limit: int = Query(default=50, ge=1, le=200),
    staff: CurrentUser = Depends(require_role()),
) -> list[AdminDepositView]:
    async with db.transaction() as conn:
        return [AdminDepositView(**d) for d in await deposits.list_for_admin(conn, status, limit)]


@router.post("/deposits/{deposit_id}/approve", response_model=BalanceChange)
async def approve(deposit_id: UUID, body: ApproveDeposit, staff: CurrentUser = Depends(finance)) -> BalanceChange:
    async with db.transaction(actor_id=staff.id) as conn:
        with business_errors():
            return BalanceChange(**await deposits.approve(conn, deposit_id, staff.id, body.amount, body.note))


@router.post("/deposits/{deposit_id}/reject", response_model=DepositView)
async def reject(deposit_id: UUID, body: RejectDeposit, staff: CurrentUser = Depends(finance)) -> DepositView:
    async with db.transaction(actor_id=staff.id) as conn:
        with business_errors():
            await deposits.reject(conn, deposit_id, staff.id, body.reason)
        return DepositView(**await deposits.get(conn, deposit_id))


@router.post("/users/{public_id}/credit", response_model=BalanceChange)
async def credit_user(
    body: CreditRequest,
    public_id: str = Path(pattern=r"^6[0-9]{9}$"),
    idempotency_key: str = Header(min_length=8, max_length=100, alias="Idempotency-Key"),
    staff: CurrentUser = Depends(finance),
) -> BalanceChange:
    """Crédit manuel autorisé (§31). La même clé d'idempotence ne crédite qu'une fois."""
    async with db.transaction(actor_id=staff.id) as conn:
        with business_errors():
            r = await deposits.admin_credit(conn, public_id, staff.id, body.amount, body.reason,
                                            f"{staff.id}:{idempotency_key}")
    return BalanceChange(**r)
