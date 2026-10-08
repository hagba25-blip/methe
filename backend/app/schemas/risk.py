from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

AccountStatus = Literal["active", "suspended", "blocked", "closed"]


class RiskEventView(BaseModel):
    id: int
    kind: str
    severity: int
    reference: str | None
    details: dict
    created_at: datetime
    resolved_at: datetime | None
    resolution_note: str | None
    resolved_by_name: str | None
    client_id: str | None
    client_name: str | None
    client_status: str | None


class ResolveRisk(BaseModel):
    note: str = Field(min_length=3, max_length=500)


class SetAccountStatus(BaseModel):
    status: AccountStatus
    reason: str = Field(min_length=3, max_length=300)

