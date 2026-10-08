"""Alertes anti-fraude et statut des comptes (administration)."""

from uuid import UUID

from psycopg import AsyncConnection

EVENT_COLUMNS = """
  e.id, e.kind, e.severity, e.reference, e.details, e.created_at, e.resolved_at, e.resolution_note,
  p.public_id as client_id, p.first_name || ' ' || p.last_name as client_name, p.status::text as client_status,
  r.first_name || ' ' || r.last_name as resolved_by_name
"""
EVENT_FROM = """
  from public.risk_events e
  left join public.profiles p on p.id = e.user_id
  left join public.profiles r on r.id = e.resolved_by
"""


async def list_events(
    conn: AsyncConnection, state: str, client_id: str | None, limit: int, before: int | None
) -> list[dict]:
    cur = await conn.execute(
        f"""
        select {EVENT_COLUMNS} {EVENT_FROM}
        where (%(state)s = 'all' or (%(state)s = 'open') = (e.resolved_at is null))
          and (%(client)s::text is null or p.public_id = %(client)s::text)
          and (%(before)s::bigint is null or e.id < %(before)s)
        order by e.id desc limit %(limit)s
        """,
        {"state": state, "client": client_id, "before": before, "limit": limit},
    )
    return await cur.fetchall()


async def get_event(conn: AsyncConnection, event_id: int) -> dict | None:
    cur = await conn.execute(f"select {EVENT_COLUMNS} {EVENT_FROM} where e.id = %s", (event_id,))
    return await cur.fetchone()


async def resolve(conn: AsyncConnection, event_id: int, admin_id: UUID, note: str) -> None:
    await conn.execute("select private.resolve_risk_event(%s, %s, %s)", (event_id, admin_id, note))


async def set_account_status(conn: AsyncConnection, public_id: str, admin_id: UUID, status: str, reason: str) -> None:
    await conn.execute("select private.set_account_status(%s, %s, %s, %s)", (public_id, admin_id, status, reason))

