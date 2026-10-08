from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status

from app import db
from app.repositories import profiles, risk
from app.schemas.profile import AdminUserView
from app.schemas.risk import ResolveRisk, RiskEventView, SetAccountStatus
from app.security.auth import CurrentUser
from app.security.roles import StaffRole, require_role
from app.services.db_errors import business_errors

router = APIRouter(prefix="/v1/admin", tags=["administration"])

reviewers = require_role(StaffRole.FINANCE, StaffRole.ADMIN, StaffRole.SUPER_ADMIN)
admin = require_role(StaffRole.ADMIN, StaffRole.SUPER_ADMIN)


@router.get("/risk-events", response_model=list[RiskEventView])
async def list_risk_events(
    state: Literal["open", "resolved", "all"] = "open",
    client_id: str | None = Query(default=None, pattern=r"^6[0-9]{9}$"),
    limit: int = Query(default=50, ge=1, le=200),
    before: int | None = Query(default=None, ge=1),
    staff: CurrentUser = Depends(require_role()),
) -> list[RiskEventView]:
    """Alertes anti-fraude : numéro de paiement partagé, mises trop faibles avant retrait,
    retrait juste après un dépôt, gros gain. À examiner avant de payer un retrait."""
    async with db.transaction() as conn:
        return [RiskEventView(**e) for e in await risk.list_events(conn, state, client_id, limit, before)]


@router.post("/risk-events/{event_id}/resolve", response_model=RiskEventView)
async def resolve_risk_event(event_id: int, body: ResolveRisk, staff: CurrentUser = Depends(reviewers)) -> RiskEventView:
    async with db.transaction(actor_id=staff.id) as conn:
        with business_errors():
            await risk.resolve(conn, event_id, staff.id, body.note)
        return RiskEventView(**await risk.get_event(conn, event_id))


@router.post("/users/{public_id}/status", response_model=AdminUserView)
async def set_account_status(
    body: SetAccountStatus,
    public_id: str = Path(pattern=r"^6[0-9]{9}$"),
    staff: CurrentUser = Depends(admin),
) -> AdminUserView:
    """Suspendre (plus de paris, dépôts ni retraits), bloquer (en plus, portefeuille gelé) ou réactiver un compte."""
    async with db.transaction(actor_id=staff.id) as conn:
        with business_errors():
            await risk.set_account_status(conn, public_id, staff.id, body.status, body.reason)
        row = await profiles.admin_lookup_by_public_id(conn, public_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Aucun client avec cet ID")
    return AdminUserView(**row)
