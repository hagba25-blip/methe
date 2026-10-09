from uuid import UUID

from pydantic import BaseModel, Field


class LoginStart(BaseModel):
    identifier: str = Field(min_length=3, max_length=254, description="ID client (10 chiffres) ou adresse e-mail")
    password: str = Field(min_length=1, max_length=200)


class LoginChallenge(BaseModel):
    challenge_id: UUID
    email_hint: str
    expires_in: int
    notice: str | None = None


class LoginVerify(BaseModel):
    challenge_id: UUID
    code: str = Field(pattern=r"^[0-9]{6,10}$")


class LoginResend(BaseModel):
    challenge_id: UUID


class LoginSession(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int
