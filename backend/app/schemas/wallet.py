from datetime import datetime

from pydantic import BaseModel


class WalletResponse(BaseModel):
    currency_code: str
    currency_decimals: int
    balance: int
    is_frozen: bool


class TransactionItem(BaseModel):
    id: int
    reference: str
    tx_type: str
    label: str
    amount: int
    balance_before: int
    balance_after: int
    status: str
    created_at: datetime


class TransactionPage(BaseModel):
    items: list[TransactionItem]
    next_cursor: int | None


TX_LABELS = {
    "deposit": "Dépôt",
    "withdrawal_hold": "Retrait (en cours)",
    "withdrawal_release": "Retrait annulé",
    "withdrawal_payout": "Retrait",
    "bet_stake": "Mise",
    "bet_win": "Gain pari",
    "bet_refund": "Remboursement",
    "adjustment": "Ajustement",
    "treasury_funding": "Trésorerie",
}

# Filtres proposés à l'utilisateur dans « Mes transactions »
TX_FILTERS = {
    "deposits": ["deposit"],
    "withdrawals": ["withdrawal_hold", "withdrawal_release", "withdrawal_payout"],
    "bets": ["bet_stake", "bet_win", "bet_refund"],
    "adjustments": ["adjustment"],
}
