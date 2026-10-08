from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class AgentView(BaseModel):
    id: UUID
    display_name: str
    whatsapp_number: str
    avatar_url: str | None
    is_available: bool


class DepositRequest(BaseModel):
    agent_id: UUID
    amount: int = Field(gt=0, le=10**12)


class DepositView(BaseModel):
    id: UUID
    reference: str
    amount: int
    currency_code: str
    status: str
    created_at: datetime
    reviewed_at: datetime | None
    rejection_reason: str | None
    agent_name: str | None
    agent_whatsapp: str | None


class DepositCreated(BaseModel):
    deposit: DepositView
    whatsapp_url: str
    message: str


class AdminDepositView(DepositView):
    client_id: str
    client_name: str
    client_phone: str


class ApproveDeposit(BaseModel):
    amount: int | None = Field(default=None, gt=0, description="Montant réellement reçu, si différent")
    note: str | None = Field(default=None, max_length=300)


class RejectDeposit(BaseModel):
    reason: str = Field(min_length=3, max_length=300)


class CreditRequest(BaseModel):
    amount: int = Field(gt=0, le=10**12)
    reason: str = Field(min_length=3, max_length=300)


class BalanceChange(BaseModel):
    reference: str
    amount: int
    balance_before: int
    balance_after: int
