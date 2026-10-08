from fastapi import APIRouter, Depends, Request

from app import db
from app.config import Settings, get_settings
from app.repositories import reference
from app.schemas.profile import LocaleResponse
from app.services.locale import guess_locale

router = APIRouter(prefix="/v1/locale", tags=["localisation"])


@router.get("/detect", response_model=LocaleResponse)
async def detect(request: Request, settings: Settings = Depends(get_settings)) -> LocaleResponse:
    """Suggestion de pays / langue / devise / indicatif pour l'inscription (public)."""
    async with db.transaction() as conn:
        countries = await reference.active_countries(conn)
        languages = await reference.active_languages(conn)
    guess = guess_locale(dict(request.headers), countries, languages, settings.default_country)
    return LocaleResponse(**guess.__dict__)
