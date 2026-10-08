from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app import db
from app.repositories import deposits, profiles, settings
from app.schemas.deposit import AgentView, DepositCreated, DepositRequest, DepositView
from app.security.auth import CurrentUser, get_current_user
from app.services import whatsapp
from app.services.db_errors import business_errors

router = APIRouter(prefix="/v1", tags=["dépôts"])


@router.get("/agents", response_model=list[AgentView])
async def list_agents() -> list[AgentView]:
    async with db.transaction() as conn:
        return [AgentView(**a) for a in await deposits.active_agents(conn)]


@router.post("/deposits", response_model=DepositCreated, status_code=status.HTTP_201_CREATED)
async def create_deposit(body: DepositRequest, user: CurrentUser = Depends(get_current_user)) -> DepositCreated:
    """Enregistre la demande (EN ATTENTE) et renvoie le lien WhatsApp pré-rempli.

    Le compte n'est crédité qu'après validation par l'administration.
    """
    async with db.transaction(actor_id=user.id) as conn:
        me = await profiles.get_profile_with_wallet(conn, user.id)
        if me is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Profil introuvable")
        with business_errors():
            deposit_id = await deposits.request(conn, user.id, body.agent_id, body.amount)
        dep = await deposits.get(conn, deposit_id)
        template = (await settings.public_settings(conn)).get("deposit.whatsapp_template")
    text = whatsapp.deposit_message(me["public_id"], template if isinstance(template, str) else None)
    return DepositCreated(
        deposit=DepositView(**dep),
        whatsapp_url=whatsapp.chat_url(dep["agent_whatsapp"], text),
        message=text,
    )


@router.get("/deposits", response_model=list[DepositView])
async def my_deposits(
    user: CurrentUser = Depends(get_current_user), limit: int = Query(default=20, ge=1, le=100)
) -> list[DepositView]:
    async with db.transaction() as conn:
        return [DepositView(**d) for d in await deposits.list_for_user(conn, user.id, limit)]


@router.post("/deposits/{deposit_id}/cancel", response_model=DepositView)
async def cancel_deposit(deposit_id: UUID, user: CurrentUser = Depends(get_current_user)) -> DepositView:
    async with db.transaction(actor_id=user.id) as conn:
        with business_errors():
            await deposits.cancel(conn, deposit_id, user.id)
        return DepositView(**await deposits.get(conn, deposit_id))
