"""Rôles d'administration : toujours lus en base (admin_users), jamais dans le jeton."""

from enum import StrEnum

from fastapi import Depends, HTTPException, status

from app import db
from app.security.auth import CurrentUser, get_current_user


class StaffRole(StrEnum):
    SUPPORT = "support"
    FINANCE = "finance"
    ADMIN = "admin"
    SUPER_ADMIN = "super_admin"


ALL_STAFF = frozenset(StaffRole)


def require_role(*allowed: StaffRole):
    allowed_set = frozenset(allowed) or ALL_STAFF

    async def dependency(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        async with db.transaction() as conn:
            cur = await conn.execute(
                "select role from public.admin_users where user_id = %s and is_active",
                (user.id,),
            )
            row = await cur.fetchone()
        if row is None or StaffRole(row["role"]) not in allowed_set:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Accès réservé à l'administration")
        return user

    return dependency
