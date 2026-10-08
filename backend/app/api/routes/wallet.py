from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app import db
from app.repositories import wallet
from app.schemas.wallet import TX_FILTERS, TX_LABELS, TransactionItem, TransactionPage, WalletResponse
from app.security.auth import CurrentUser, get_current_user

router = APIRouter(prefix="/v1/wallet", tags=["portefeuille"])


@router.get("", response_model=WalletResponse)
async def get_wallet(user: CurrentUser = Depends(get_current_user)) -> WalletResponse:
    async with db.transaction() as conn:
        row = await wallet.get_user_wallet(conn, user.id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Portefeuille introuvable")
    return WalletResponse(**row)


@router.get("/transactions", response_model=TransactionPage)
async def list_transactions(
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(default=20, ge=1, le=100),
    cursor: int | None = Query(default=None, ge=1, description="next_cursor de la page précédente"),
    kind: Literal["deposits", "withdrawals", "bets", "adjustments"] | None = None,
) -> TransactionPage:
    async with db.transaction() as conn:
        rows = await wallet.list_user_transactions(
            conn, user.id, limit + 1, cursor, TX_FILTERS[kind] if kind else None)
    has_more = len(rows) > limit
    rows = rows[:limit]
    items = [
        TransactionItem(**{k: v for k, v in r.items() if k != "description"},
                        label=TX_LABELS.get(r["tx_type"], r["tx_type"]))
        for r in rows
    ]
    return TransactionPage(items=items, next_cursor=items[-1].id if has_more and items else None)
