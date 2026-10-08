from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app import db
from app.repositories import profiles, support
from app.schemas.support import HelpCenter, NewMessage, NewTicket, SupportContact, TicketDetail, TicketSummary
from app.security.auth import CurrentUser, get_current_user
from app.services import whatsapp
from app.services.db_errors import business_errors

router = APIRouter(prefix="/v1/support", tags=["support"])


async def _detail(conn, ticket_id: UUID, user_id: UUID) -> TicketDetail:
    ticket = await support.get(conn, ticket_id, staff=False, user_id=user_id)
    if ticket is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Demande introuvable")
    return TicketDetail(**ticket)


@router.get("/help", response_model=HelpCenter)
async def help_center(
    language: str = Query(default="fr", pattern=r"^[a-z]{2}$"),
    user: CurrentUser = Depends(get_current_user),
) -> HelpCenter:
    """Questions fréquentes publiées et moyens de contacter le support (WhatsApp, horaires)."""
    async with db.transaction() as conn:
        entries = await support.faq(conn, language)
        contact = await support.contact_settings(conn)
        me = await profiles.get_profile_with_wallet(conn, user.id)
    number = contact.get("support.whatsapp_number")
    url = None
    if isinstance(number, str) and number.strip():
        text = "Bonjour, j'ai besoin d'aide." + (f" ID client : {me['public_id']}" if me else "")
        url = whatsapp.chat_url(number, text)
    hours = contact.get("support.hours")
    return HelpCenter(faq=entries, contact=SupportContact(whatsapp_url=url, hours=hours if isinstance(hours, str) else None))


@router.get("/tickets", response_model=list[TicketSummary])
async def my_tickets(
    limit: int = Query(default=30, ge=1, le=100), user: CurrentUser = Depends(get_current_user)
) -> list[TicketSummary]:
    async with db.transaction() as conn:
        return [TicketSummary(**t) for t in await support.list_for_user(conn, user.id, limit)]


@router.post("/tickets", response_model=TicketDetail, status_code=status.HTTP_201_CREATED)
async def open_ticket(body: NewTicket, user: CurrentUser = Depends(get_current_user)) -> TicketDetail:
    """Nouvelle demande d'aide. Possible même si le compte est suspendu ou bloqué."""
    async with db.transaction(actor_id=user.id) as conn:
        with business_errors():
            tid = await support.open_ticket(conn, user.id, body.category, body.subject, body.message,
                                            body.related_reference)
        return await _detail(conn, tid, user.id)


@router.get("/tickets/{ticket_id}", response_model=TicketDetail)
async def get_ticket(ticket_id: UUID, user: CurrentUser = Depends(get_current_user)) -> TicketDetail:
    """La conversation complète ; les réponses du support sont marquées comme lues."""
    async with db.transaction() as conn:
        return await _detail(conn, ticket_id, user.id)


@router.post("/tickets/{ticket_id}/messages", response_model=TicketDetail)
async def reply(ticket_id: UUID, body: NewMessage, user: CurrentUser = Depends(get_current_user)) -> TicketDetail:
    """Répondre au support ; une demande résolue est alors rouverte."""
    async with db.transaction(actor_id=user.id) as conn:
        with business_errors():
            await support.post_message(conn, ticket_id, user.id, False, body.body)
        return await _detail(conn, ticket_id, user.id)


@router.post("/tickets/{ticket_id}/close", response_model=TicketDetail)
async def close(ticket_id: UUID, user: CurrentUser = Depends(get_current_user)) -> TicketDetail:
    """Le joueur indique que son problème est réglé : la demande est fermée."""
    async with db.transaction(actor_id=user.id) as conn:
        with business_errors():
            await support.set_status(conn, ticket_id, user.id, False, "closed")
        return await _detail(conn, ticket_id, user.id)
