from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field

GameCode = Literal["FRUITS", "LONATO"]


class RoundView(BaseModel):
    id: UUID
    game_code: str
    round_number: int
    opens_at: datetime
    closes_at: datetime
    draw_at: datetime
    status: str
    commitment_hash: str | None = Field(description="SHA-256 de la graine, publié avant les mises")
    revealed_seed: str | None = Field(description="Graine révélée à la publication")
    algorithm_version: str | None
    result: dict[str, Any] | None
    drawn_at: datetime | None
    published_at: datetime | None


class Verification(BaseModel):
    round_id: UUID
    commitment_ok: bool
    result_ok: bool
    recomputed: dict[str, Any] | None
    explanation: str


class CancelRound(BaseModel):
    reason: str = Field(min_length=3, max_length=300)
