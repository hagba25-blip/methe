from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Query

from app import db
from app.repositories import dashboard
from app.schemas.dashboard import AdminActionView, Dashboard
from app.security.auth import CurrentUser
from app.security.roles import StaffRole, require_role

router = APIRouter(prefix="/v1/admin", tags=["administration"])

PERIOD_DAYS = {"today": 0, "7d": 6, "30d": 29, "90d": 89}


@router.get("/dashboard", response_model=Dashboard)
async def get_dashboard(
    period: Literal["today", "7d", "30d", "90d"] = "7d",
    currency: str = Query(default="XOF", pattern=r"^[A-Z]{3}$"),
    staff: CurrentUser = Depends(require_role()),
) -> Dashboard:
    """Vue d'ensemble : joueurs, dépôts et retraits à traiter, mises, gains versés,
    produit brut des jeux par jeu et par jour, soldes des comptes système, derniers tirages."""
    today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    since = today - timedelta(days=PERIOD_DAYS[period])
    async with db.transaction() as conn:
        data = await dashboard.overview(conn, since, currency)
        role = await dashboard.staff_role(conn, staff.id)
    return Dashboard(**data, viewer_role=role)


@router.get("/actions", response_model=list[AdminActionView])
async def list_admin_actions(
    limit: int = Query(default=30, ge=1, le=100),
    before: int | None = Query(default=None, ge=1, description="id de la dernière action de la page précédente"),
    staff: CurrentUser = Depends(require_role(StaffRole.ADMIN, StaffRole.SUPER_ADMIN)),
) -> list[AdminActionView]:
    """Journal des actions de l'administration (validations, refus, crédits, consultations de fiches)."""
    async with db.transaction() as conn:
        return [AdminActionView(**a) for a in await dashboard.admin_actions(conn, limit, before)]
