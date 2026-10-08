from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

WithdrawalMethod = Literal["mobile_money", "agent", "bank"]
WithdrawalStatus = Literal["pending", "under_review", "approved", "paid", "rejected", "cancelled"]


class WithdrawalInfo(BaseModel):
    balance: int
    currency_code: str
    min_amount: int
    max_amount: int | None
    fee_percent: float
    can_withdraw: bool
    blocked_reason: str | None
    default_payout_account: str | None


class WithdrawalRequest(BaseModel):
    amount: int = Field(gt=0, le=10**12)
    method: WithdrawalMethod = "mobile_money"
    payout_account: str = Field(min_length=6, max_length=80)


class WithdrawalView(BaseModel):
    id: UUID
    reference: str
    amount: int
    fee: int
    net_amount: int
    currency_code: str
    method: str
    payout_account: str
    status: str
    created_at: datetime
    reviewed_at: datetime | None
    paid_at: datetime | None
    rejection_reason: str | None


class AdminWithdrawalView(WithdrawalView):
    client_id: str
    client_name: str
    client_phone: str
    client_balance: int


class ProcessWithdrawal(BaseModel):
    reason: str | None = Field(default=None, max_length=300)
