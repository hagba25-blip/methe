from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status

from app import db
from app.draw import verify
from app.repositories import rounds
from app.schemas.round import GameCode, RoundView, Verification

router = APIRouter(prefix="/v1/rounds", tags=["tirages"])


@router.get("/upcoming", response_model=list[RoundView])
async def upcoming(game: GameCode) -> list[RoundView]:
    """Tour en cours (avec son empreinte publiée) et tours suivants."""
    async with db.transaction() as conn:
        return [RoundView(**r) for r in await rounds.upcoming(conn, game)]


@router.get("/results", response_model=list[RoundView])
async def results(
    game: GameCode,
    limit: int = Query(default=20, ge=1, le=100),
    before: datetime | None = Query(default=None, description="draw_at du dernier élément de la page précédente"),
) -> list[RoundView]:
    async with db.transaction() as conn:
        return [RoundView(**r) for r in await rounds.results(conn, game, limit, before)]


@router.get("/{round_id}", response_model=RoundView)
async def get_round(round_id: UUID) -> RoundView:
    async with db.transaction() as conn:
        row = await rounds.get(conn, round_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Tirage introuvable")
    return RoundView(**row)


@router.get("/{round_id}/verify", response_model=Verification)
async def verify_round(round_id: UUID) -> Verification:
    """Recalcule le résultat à partir de la graine révélée (preuve d'équité)."""
    async with db.transaction() as conn:
        row = await rounds.get(conn, round_id)
        symbols = await rounds.fruit_symbols(conn)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Tirage introuvable")
    return Verification(**verify.verify(row, symbols))
