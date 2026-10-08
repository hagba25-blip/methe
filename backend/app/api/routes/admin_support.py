from datetime import datetime
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app import db
from app.repositories import support
from app.schemas.support import FaqAdminEntry, FaqPatch, FaqWrite, NewMessage, SetTicketStatus, TicketDetail, TicketSummary
from app.security.auth import CurrentUser
from app.security.roles import StaffRole, require_role
from app.services.db_errors import business_errors

router = APIRouter(prefix="/v1/admin", tags=["administration"])

faq_editors = require_role(StaffRole.SUPPORT, StaffRole.ADMIN, StaffRole.SUPER_ADMIN)


async def _detail(conn, ticket_id: UUID) -> TicketDetail:
    ticket = await support.get(conn, ticket_id, staff=True)
    if ticket is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Demande introuvable")
    return TicketDetail(**ticket)


@router.get("/support/tickets", response_model=list[TicketSummary])
async def support_queue(
    state: Literal["todo", "answered", "done", "all"] = "todo",
    client_id: str | None = Query(default=None, pattern=r"^6[0-9]{9}$"),
    limit: int = Query(default=50, ge=1, le=200),
    before: datetime | None = Query(default=None, description="last_message_at de la dernière demande de la page"),
    staff: CurrentUser = Depends(require_role()),
) -> list[TicketSummary]:
    """« À traiter » : la plus ancienne en premier. Les autres filtres : la plus récente en premier."""
    async with db.transaction() as conn:
        return [TicketSummary(**t) for t in await support.queue(conn, state, client_id, limit, before)]


@router.get("/support/tickets/{ticket_id}", response_model=TicketDetail)
async def support_ticket(ticket_id: UUID, staff: CurrentUser = Depends(require_role())) -> TicketDetail:
    async with db.transaction() as conn:
        return await _detail(conn, ticket_id)


@router.post("/support/tickets/{ticket_id}/messages", response_model=TicketDetail)
async def support_reply(ticket_id: UUID, body: NewMessage, staff: CurrentUser = Depends(require_role())) -> TicketDetail:
    """Répondre au joueur : il reçoit une notification ; la demande passe à « Répondu »."""
    async with db.transaction(actor_id=staff.id) as conn:
        with business_errors():
            await support.post_message(conn, ticket_id, staff.id, True, body.body)
        return await _detail(conn, ticket_id)


@router.post("/support/tickets/{ticket_id}/status", response_model=TicketDetail)
async def support_status(ticket_id: UUID, body: SetTicketStatus, staff: CurrentUser = Depends(require_role())) -> TicketDetail:
    """Résoudre (le joueur peut rouvrir en répondant), fermer définitivement, ou remettre à traiter."""
    async with db.transaction(actor_id=staff.id) as conn:
        with business_errors():
            await support.set_status(conn, ticket_id, staff.id, True, body.status)
        return await _detail(conn, ticket_id)


@router.get("/faq", response_model=list[FaqAdminEntry])
async def faq_list(staff: CurrentUser = Depends(require_role())) -> list[FaqAdminEntry]:
    """Toutes les questions fréquentes, y compris les brouillons non publiés."""
    async with db.transaction() as conn:
        return [FaqAdminEntry(**f) for f in await support.faq_all(conn)]


@router.post("/faq", response_model=FaqAdminEntry, status_code=status.HTTP_201_CREATED)
async def faq_create(body: FaqWrite, staff: CurrentUser = Depends(faq_editors)) -> FaqAdminEntry:
    async with db.transaction(actor_id=staff.id) as conn:
        return FaqAdminEntry(**await support.faq_create(conn, staff.id, body.model_dump()))


@router.patch("/faq/{faq_id}", response_model=FaqAdminEntry)
async def faq_update(faq_id: int, body: FaqPatch, staff: CurrentUser = Depends(faq_editors)) -> FaqAdminEntry:
    changes = body.model_dump(exclude_none=True)
    for key in ("question", "answer"):
        if key in changes:
            changes[key] = changes[key].strip()
    async with db.transaction(actor_id=staff.id) as conn:
        row = await support.faq_update(conn, faq_id, staff.id, changes)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Question introuvable")
    return FaqAdminEntry(**row)


@router.delete("/faq/{faq_id}", status_code=status.HTTP_204_NO_CONTENT)
async def faq_delete(faq_id: int, staff: CurrentUser = Depends(faq_editors)) -> None:
    async with db.transaction(actor_id=staff.id) as conn:
        if not await support.faq_delete(conn, faq_id):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Question introuvable")
