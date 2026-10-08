from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, status

from app import db
from app.repositories import withdrawals
from app.schemas.withdrawal import WithdrawalInfo, WithdrawalRequest, WithdrawalView
from app.security.auth import CurrentUser, get_current_user
from app.services.db_errors import business_errors

router = APIRouter(prefix="/v1", tags=["retraits"])


@router.get("/withdrawals/info", response_model=WithdrawalInfo)
async def withdrawal_info(user: CurrentUser = Depends(get_current_user)) -> WithdrawalInfo:
    """Solde, limites, frais et raison éventuelle d'un blocage, pour l'écran Retrait."""
    async with db.transaction() as conn:
        return WithdrawalInfo(**await withdrawals.info(conn, user.id))


@router.post("/withdrawals", response_model=WithdrawalView, status_code=status.HTTP_201_CREATED)
async def create_withdrawal(
    body: WithdrawalRequest,
    idempotency_key: str = Header(min_length=8, max_length=100, alias="Idempotency-Key"),
    user: CurrentUser = Depends(get_current_user),
) -> WithdrawalView:
    """Crée la demande (EN ATTENTE) et bloque immédiatement le montant sur le solde.

    Un double envoi avec la même clé renvoie la même demande sans second débit.
    """
    async with db.transaction(actor_id=user.id) as conn:
        with business_errors():
            wid = await withdrawals.request(conn, user.id, body.amount, body.method, body.payout_account,
                                            idempotency_key)
        return WithdrawalView(**await withdrawals.get(conn, wid))


@router.get("/withdrawals", response_model=list[WithdrawalView])
async def my_withdrawals(
    user: CurrentUser = Depends(get_current_user), limit: int = Query(default=20, ge=1, le=100)
) -> list[WithdrawalView]:
    async with db.transaction() as conn:
        return [WithdrawalView(**w) for w in await withdrawals.list_for_user(conn, user.id, limit)]


@router.post("/withdrawals/{withdrawal_id}/cancel", response_model=WithdrawalView)
async def cancel_withdrawal(withdrawal_id: UUID, user: CurrentUser = Depends(get_current_user)) -> WithdrawalView:
    async with db.transaction(actor_id=user.id) as conn:
        with business_errors():
            await withdrawals.cancel(conn, withdrawal_id, user.id)
        return WithdrawalView(**await withdrawals.get(conn, withdrawal_id))
