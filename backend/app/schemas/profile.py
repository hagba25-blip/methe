from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class MeResponse(BaseModel):
    id: UUID
    public_id: str
    first_name: str
    last_name: str
    phone: str
    email: str | None
    country_code: str
    language_code: str
    currency_code: str
    currency_decimals: int
    avatar_url: str | None
    status: str
    kyc_status: str
    balance: int            # unités mineures de la devise
    is_staff: bool
    created_at: datetime


class LocaleResponse(BaseModel):
    country_code: str
    dial_code: str
    currency_code: str
    language_code: str
    detected: bool
