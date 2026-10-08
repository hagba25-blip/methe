from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status

from app import db
from app.repositories import bets
from app.schemas.bet import BetFilter, BetRequest, BetSummary, BetView, GameView, PoolState
from app.security.auth import CurrentUser, get_current_user
from app.services.db_errors import business_errors

router = APIRouter(prefix="/v1", tags=["paris"])


@router.get("/games", response_model=list[GameView])
async def games() -> list[GameView]:
    """Jeux, types de pari, cotes jouables (version en vigueur) et symboles."""
    async with db.transaction() as conn:
        return [GameView(**g) for g in await bets.catalog(conn)]


@router.get("/rounds/{round_id}/pool", response_model=PoolState)
async def pool(round_id: UUID) -> PoolState:
    """Cagnotte d'un tour en pari mutuel, pour estimer le gain avant la fermeture.

    Gain estimé si le fruit f sort = (cagnotte + mise) × (1 − commission) × w ÷ (poids_f + w),
    avec w = mise × poids. Le partage définitif est calculé au tirage.
    """
    async with db.transaction() as conn:
        return PoolState(round_id=round_id, **await bets.pool_state(conn, round_id))


@router.post("/bets", response_model=BetView, status_code=status.HTTP_201_CREATED)
async def place_bet(
    body: BetRequest,
    idempotency_key: str = Header(min_length=8, max_length=100, alias="Idempotency-Key"),
    user: CurrentUser = Depends(get_current_user),
) -> BetView:
    """Débite la mise et enregistre le pari avec les cotes en vigueur.

    Tout est vérifié par la base : tour ouvert, sélection, cote publiée, solde.
    Un double envoi avec la même clé renvoie le même pari sans second débit.
    """
    async with db.transaction(actor_id=user.id) as conn:
        with business_errors():
            bet_id = await bets.place(conn, user.id, body.round_id, body.game_type, body.selections, body.stake,
                                      idempotency_key)
        return BetView(**await bets.get(conn, bet_id, user.id))


@router.get("/bets", response_model=list[BetView])
async def my_bets(
    user: CurrentUser = Depends(get_current_user),
    status_filter: list[BetFilter] | None = Query(default=None, alias="status"),
    game: str | None = Query(default=None, pattern=r"^[A-Z]{2,30}$"),
    limit: int = Query(default=20, ge=1, le=100),
    before: datetime | None = Query(default=None, description="placed_at du dernier pari de la page précédente"),
    since: datetime | None = Query(default=None, description="paris placés à partir de cette date"),
) -> list[BetView]:
    async with db.transaction() as conn:
        rows = await bets.list_for_user(conn, user.id, status_filter, game, limit, before, since)
    return [BetView(**r) for r in rows]


@router.get("/bets/summary", response_model=BetSummary)
async def my_bets_summary(
    user: CurrentUser = Depends(get_current_user),
    game: str | None = Query(default=None, pattern=r"^[A-Z]{2,30}$"),
    since: datetime | None = Query(default=None, description="paris placés à partir de cette date"),
) -> BetSummary:
    """Bilan du joueur : nombre de paris, total misé, total gagné, résultat net des paris réglés."""
    async with db.transaction() as conn:
        return BetSummary(**await bets.summary(conn, user.id, game, since))


@router.get("/bets/{bet_id}", response_model=BetView)
async def get_bet(bet_id: UUID, user: CurrentUser = Depends(get_current_user)) -> BetView:
    async with db.transaction() as conn:
        row = await bets.get(conn, bet_id, user.id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pari introuvable")
    return BetView(**row)
