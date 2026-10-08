from fastapi import APIRouter, Depends, HTTPException, status

from app import db
from app.repositories import profiles
from app.schemas.profile import MeResponse
from app.security.auth import CurrentUser, get_current_user

router = APIRouter(prefix="/v1/me", tags=["compte"])


@router.get("", response_model=MeResponse)
async def me(user: CurrentUser = Depends(get_current_user)) -> MeResponse:
    async with db.transaction(actor_id=user.id) as conn:
        row = await profiles.get_profile_with_wallet(conn, user.id)
        if row is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Profil introuvable")
        await profiles.touch_last_login(conn, user.id)
    return MeResponse(**row)
