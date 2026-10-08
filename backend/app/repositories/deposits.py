from uuid import UUID

from psycopg import AsyncConnection

DEPOSIT_COLUMNS = """
  d.id, d.reference, d.amount, d.currency_code, d.status, d.created_at, d.reviewed_at,
  d.rejection_reason, a.display_name as agent_name, a.whatsapp_number as agent_whatsapp
"""


async def active_agents(conn: AsyncConnection) -> list[dict]:
    cur = await conn.execute(
        "select id, display_name, whatsapp_number, avatar_url, is_available "
        "from public.agents where is_active order by sort_order, display_name"
    )
    return await cur.fetchall()


async def get_agent(conn: AsyncConnection, agent_id: UUID) -> dict | None:
    cur = await conn.execute("select * from public.agents where id = %s", (agent_id,))
    return await cur.fetchone()


async def request(conn: AsyncConnection, user_id: UUID, agent_id: UUID, amount: int) -> UUID:
    cur = await conn.execute("select (private.request_deposit(%s, %s, %s)).id", (user_id, agent_id, amount))
    return (await cur.fetchone())["id"]


async def cancel(conn: AsyncConnection, deposit_id: UUID, user_id: UUID) -> None:
    await conn.execute("select private.cancel_deposit(%s, %s)", (deposit_id, user_id))


async def get(conn: AsyncConnection, deposit_id: UUID) -> dict | None:
    cur = await conn.execute(
        f"select {DEPOSIT_COLUMNS} from public.deposits d left join public.agents a on a.id = d.agent_id "
        "where d.id = %s",
        (deposit_id,),
    )
    return await cur.fetchone()


async def list_for_user(conn: AsyncConnection, user_id: UUID, limit: int) -> list[dict]:
    cur = await conn.execute(
        f"select {DEPOSIT_COLUMNS} from public.deposits d left join public.agents a on a.id = d.agent_id "
        "where d.user_id = %s order by d.created_at desc limit %s",
        (user_id, limit),
    )
    return await cur.fetchall()


async def list_for_admin(conn: AsyncConnection, status: str | None, limit: int) -> list[dict]:
    cur = await conn.execute(
        f"""
        select {DEPOSIT_COLUMNS}, p.public_id as client_id, p.first_name || ' ' || p.last_name as client_name,
               p.phone as client_phone
        from public.deposits d
        join public.profiles p on p.id = d.user_id
        left join public.agents a on a.id = d.agent_id
        where (%(status)s::public.deposit_status is null or d.status = %(status)s::public.deposit_status)
        order by d.created_at {'asc' if status == 'pending' else 'desc'}
        limit %(limit)s
        """,
        {"status": status, "limit": limit},
    )
    return await cur.fetchall()


async def approve(conn: AsyncConnection, deposit_id: UUID, admin_id: UUID, amount: int | None, note: str | None) -> dict:
    cur = await conn.execute("select private.approve_deposit(%s, %s, %s, %s) as r", (deposit_id, admin_id, amount, note))
    return (await cur.fetchone())["r"]


async def reject(conn: AsyncConnection, deposit_id: UUID, admin_id: UUID, reason: str) -> None:
    await conn.execute("select private.reject_deposit(%s, %s, %s)", (deposit_id, admin_id, reason))


async def admin_credit(conn: AsyncConnection, public_id: str, admin_id: UUID, amount: int, reason: str, key: str) -> dict:
    cur = await conn.execute(
        "select private.admin_credit(%s, %s, %s, %s, %s) as r", (public_id, admin_id, amount, reason, key)
    )
    return (await cur.fetchone())["r"]
