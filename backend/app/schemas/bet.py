from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field


class GameTypeView(BaseModel):
    code: str
    name: str
    min_selection: int
    max_selection: int
    min_stake: int
    settlement_mode: Literal["fixed", "pool"] = Field(
        description="fixed : gain = mise × cote ; pool : pari mutuel, les cotes sont des poids")
    commission_percent: float | None = Field(description="Commission sur la cagnotte (pari mutuel)")
    odds: dict[str, dict[str, float]] = Field(
        description="Cotes (ou poids en mutuel) jouables : nombre choisi → {nombre trouvé → valeur}")


class SymbolView(BaseModel):
    code: str
    label: str
    emoji: str | None


class GameView(BaseModel):
    code: str
    name: str
    description: str | None
    interval_minutes: int | None
    close_before_seconds: int | None
    types: list[GameTypeView]
    symbols: list[SymbolView]


class BetRequest(BaseModel):
    round_id: UUID
    game_type: str = Field(pattern=r"^[A-Z_]{2,30}$")
    selections: list[str] = Field(min_length=1, max_length=20)
    stake: int = Field(gt=0, le=10**12)


class BetView(BaseModel):
    id: UUID
    reference: str
    round_id: UUID
    round_number: int
    draw_at: datetime
    round_status: str
    round_result: dict[str, Any] | None
    game_code: str
    game_type_code: str
    selection_count: int
    selections: list[str]
    matched_values: list[str]
    stake: int
    currency_code: str
    odds_snapshot: dict[str, float]
    potential_payout: int
    status: str
    actual_payout: int
    placed_at: datetime
    settled_at: datetime | None


BetFilter = Literal["pending", "won", "lost", "refunded"]


class BetSummary(BaseModel):
    bet_count: int
    pending_count: int
    won_count: int
    lost_count: int
    total_staked: int
    pending_stake: int
    total_won: int
    best_win: int
    net: int


class PoolState(BaseModel):
    round_id: UUID
    total_stakes: int
    commission_percent: float
    bet_count: int
    weights: dict[str, float] = Field(description="Poids total (mise × poids) engagé sur chaque fruit")
