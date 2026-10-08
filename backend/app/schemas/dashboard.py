from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class UserStats(BaseModel):
    total: int
    new_in_period: int
    active_in_period: int
    restricted: int
    balances_total: int


class DepositStats(BaseModel):
    pending_count: int
    pending_amount: int
    approved_count: int
    approved_amount: int


class WithdrawalStats(BaseModel):
    open_count: int
    open_amount: int
    paid_count: int
    paid_amount: int


class BetStats(BaseModel):
    bet_count: int
    players: int
    staked: int
    pending_stake: int
    paid: int
    gross_revenue: int


class GameStats(BaseModel):
    game_code: str
    name: str
    bet_count: int
    players: int
    staked: int
    pending_stake: int
    paid: int
    gross_revenue: int


class DayStats(BaseModel):
    day: str
    staked: int
    paid: int
    deposits: int
    withdrawals: int


class SystemWallet(BaseModel):
    code: str
    balance: int


class RoundStats(BaseModel):
    id: UUID
    game_code: str
    round_number: int
    status: str
    draw_at: datetime
    result: dict | None
    bet_count: int
    staked: int
    paid: int


class RiskStats(BaseModel):
    open_count: int
    high_count: int


class SupportStats(BaseModel):
    todo_count: int
    answered_count: int
    oldest_todo_hours: int


class Dashboard(BaseModel):
    since: datetime
    currency_code: str
    viewer_role: str
    users: UserStats
    deposits: DepositStats
    withdrawals: WithdrawalStats
    risk: RiskStats
    support: SupportStats
    bets: BetStats
    games: list[GameStats]
    daily: list[DayStats]
    system_wallets: list[SystemWallet]
    recent_rounds: list[RoundStats]


class AdminActionView(BaseModel):
    id: int
    action: str
    target_type: str
    target_id: str
    reason: str | None
    created_at: datetime
    admin_public_id: str
    admin_name: str
