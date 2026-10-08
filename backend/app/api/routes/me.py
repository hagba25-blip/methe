from fastapi import APIRouter, Depends, HTTPException, status

from app import db
from app.repositories import profiles
from app.schemas.profile import MeResponse, ProfileUpdate
from app.security.auth import CurrentUser, get_current_user

router = APIRouter(prefix="/v1/me", tags=["compte"])


async def _load(conn, user: CurrentUser) -> MeResponse:
    row = await profiles.get_profile_with_wallet(conn, user.id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Profil introuvable")
    return MeResponse(**row)


@router.get("", response_model=MeResponse)
async def me(user: CurrentUser = Depends(get_current_user)) -> MeResponse:
    async with db.transaction(actor_id=user.id) as conn:
        result = await _load(conn, user)
        await profiles.touch_last_login(conn, user.id)
    return result


@router.patch("", response_model=MeResponse)
async def update_me(body: ProfileUpdate, user: CurrentUser = Depends(get_current_user)) -> MeResponse:
    """Seuls prénom, nom, langue et avatar sont modifiables ; l'ID client ne l'est jamais."""
    changes = body.model_dump(exclude_unset=True, exclude_none=True)
    async with db.transaction(actor_id=user.id) as conn:
        current = await _load(conn, user)
        if current.status != "active":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Compte non actif")
        if "language_code" in changes and not await profiles.language_exists(conn, changes["language_code"]):
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Langue non prise en charge")
        await profiles.update_profile(conn, user.id, changes)
        return await _load(conn, user)
