from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

TicketCategory = Literal["deposit", "withdrawal", "bet", "account", "technical", "other"]
TicketStatus = Literal["open", "answered", "resolved", "closed"]
FaqCategory = Literal["account", "deposit", "withdrawal", "games", "security"]


class FaqEntry(BaseModel):
    id: int
    category: FaqCategory
    question: str
    answer: str


class FaqAdminEntry(FaqEntry):
    language_code: str
    sort_order: int
    is_published: bool
    updated_at: datetime


class FaqWrite(BaseModel):
    category: FaqCategory
    question: str = Field(min_length=5, max_length=200)
    answer: str = Field(min_length=5, max_length=4000)
    language_code: str = Field(default="fr", pattern=r"^[a-z]{2}$")
    sort_order: int = Field(default=100, ge=0, le=10000)
    is_published: bool = True


class FaqPatch(BaseModel):
    category: FaqCategory | None = None
    question: str | None = Field(default=None, min_length=5, max_length=200)
    answer: str | None = Field(default=None, min_length=5, max_length=4000)
    sort_order: int | None = Field(default=None, ge=0, le=10000)
    is_published: bool | None = None


class SupportContact(BaseModel):
    whatsapp_url: str | None
    hours: str | None


class HelpCenter(BaseModel):
    faq: list[FaqEntry]
    contact: SupportContact


class NewTicket(BaseModel):
    category: TicketCategory
    subject: str = Field(min_length=3, max_length=120)
    message: str = Field(min_length=1, max_length=2000)
    related_reference: str | None = Field(default=None, max_length=40)


class NewMessage(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class SetTicketStatus(BaseModel):
    status: Literal["open", "resolved", "closed"]


class TicketSummary(BaseModel):
    id: UUID
    reference: str
    category: TicketCategory
    subject: str
    related_reference: str | None
    status: TicketStatus
    unread: int
    last_message_at: datetime
    created_at: datetime
    # Renseignés pour l'équipe uniquement
    client_id: str | None = None
    client_name: str | None = None
    assigned_name: str | None = None


class TicketMessage(BaseModel):
    id: int
    is_staff: bool
    author_name: str
    body: str
    created_at: datetime


class TicketDetail(TicketSummary):
    messages: list[TicketMessage]
