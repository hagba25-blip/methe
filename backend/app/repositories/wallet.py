from datetime import datetime
from uuid import UUID

from psycopg import AsyncConnection


async def get_user_wallet(conn: AsyncConnection, user_id: UUID) -> dict | None:
    cur = await conn.execute(
        """
        select w.id, w.currency_code, w.balance, w.is_frozen, c.decimals as currency_decimals
        from public.wallets w
        join public.profiles p on p.id = w.user_id and p.currency_code = w.currency_code
        join public.currencies c on c.code = w.currency_code
        where w.user_id = %s
        """,
        (user_id,),
    )
    return await cur.fetchone()


async def list_user_transactions(
    conn: AsyncConnection,
    user_id: UUID,
    limit: int,
    before_id: int | None = None,
    tx_types: list[str] | None = None,
) -> list[dict]:
    """Historique paginé par curseur (id décroissant)."""
    cur = await conn.execute(
        """
        select t.id, t.reference, t.tx_type, t.amount, t.balance_before, t.balance_after,
               t.status, t.created_at, j.description
        from public.wallet_transactions t
        join public.ledger_journals j on j.id = t.journal_id
        where t.user_id = %(user_id)s
          and (%(before_id)s::bigint is null or t.id < %(before_id)s)
          and (%(types)s::public.tx_type[] is null or t.tx_type = any(%(types)s::public.tx_type[]))
        order by t.id desc
        limit %(limit)s
        """,
        {"user_id": user_id, "before_id": before_id, "types": tx_types, "limit": limit},
    )
    return await cur.fetchall()


async def last_activity(conn: AsyncConnection, user_id: UUID) -> datetime | None:
    cur = await conn.execute(
        "select max(created_at) as at from public.wallet_transactions where user_id = %s", (user_id,)
    )
    row = await cur.fetchone()
    return row["at"] if row else None
