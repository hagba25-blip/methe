from fastapi import APIRouter

from app import db
from app.repositories import settings

router = APIRouter(prefix="/v1/settings", tags=["paramètres"])


@router.get("/public")
async def public_settings() -> dict:
    """Paramètres affichables par l'application (mise minimum, retrait minimum, …)."""
    async with db.transaction() as conn:
        return await settings.public_settings(conn)
