from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


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


class ProfileUpdate(BaseModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=80)
    last_name: str | None = Field(default=None, min_length=1, max_length=80)
    language_code: str | None = Field(default=None, pattern=r"^[a-z]{2}(-[A-Z]{2})?$")
    avatar_url: str | None = Field(default=None, max_length=500)

    @field_validator("first_name", "last_name")
    @classmethod
    def strip_names(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = " ".join(v.split())
        if not v:
            raise ValueError("Ne peut pas être vide")
        return v

    @field_validator("avatar_url")
    @classmethod
    def https_only(cls, v: str | None) -> str | None:
        if v is not None and not v.startswith("https://"):
            raise ValueError("L'avatar doit être une adresse https://")
        return v


class AdminUserView(BaseModel):
    id: UUID
    public_id: str
    first_name: str
    last_name: str
    phone: str
    email: str | None
    country_code: str
    currency_code: str
    currency_decimals: int
    status: str
    kyc_status: str
    balance: int
    created_at: datetime
    last_login_at: datetime | None
    bet_count: int
    total_staked: int
    total_won: int
    total_deposited: int
    total_withdrawn: int
