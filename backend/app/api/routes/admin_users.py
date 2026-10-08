import ipaddress

from fastapi import APIRouter, Depends, HTTPException, Path, Request, status

from app import db
from app.repositories import profiles
from app.schemas.profile import AdminUserView
from app.security.auth import CurrentUser
from app.security.roles import require_role

router = APIRouter(prefix="/v1/admin/users", tags=["administration"])


@router.get("/{public_id}", response_model=AdminUserView)
async def find_by_public_id(
    request: Request,
    public_id: str = Path(pattern=r"^6[0-9]{9}$"),
    staff: CurrentUser = Depends(require_role()),
) -> AdminUserView:
    async with db.transaction(actor_id=staff.id) as conn:
        row = await profiles.admin_lookup_by_public_id(conn, public_id)
        # Toute consultation d'une fiche client est tracée.
        await conn.execute(
            "insert into public.admin_actions (admin_id, action, target_type, target_id, ip_address) "
            "values (%s, 'view_user', 'profile', %s, %s)",
            (staff.id, public_id, _client_ip(request)),
        )
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Aucun client avec cet ID")
    return AdminUserView(**row)


def _client_ip(request: Request) -> str | None:
    host = request.client.host if request.client else None
    try:
        return str(ipaddress.ip_address(host)) if host else None
    except ValueError:
        return None
