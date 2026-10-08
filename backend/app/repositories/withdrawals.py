from uuid import UUID

from psycopg import AsyncConnection

WITHDRAWAL_COLUMNS = """
  w.id, w.reference, w.amount, w.fee, w.net_amount, w.currency_code, w.method, w.payout_account,
  w.status, w.created_at, w.reviewed_at, w.paid_at, w.rejection_reason
"""


async def info(conn: AsyncConnection, user_id: UUID) -> dict:
    cur = await conn.execute("select private.withdrawal_info(%s) as r", (user_id,))
    return (await cur.fetchone())["r"]


async def request(
    conn: AsyncConnection, user_id: UUID, amount: int, method: str, payout_account: str, key: str
) -> UUID:
    cur = await conn.execute(
        "select (private.request_withdrawal(%s, %s, %s, %s, %s)).id",
        (user_id, amount, method, payout_account, key),
    )
    return (await cur.fetchone())["id"]


async def cancel(conn: AsyncConnection, withdrawal_id: UUID, user_id: UUID) -> None:
    await conn.execute("select private.cancel_withdrawal(%s, %s)", (withdrawal_id, user_id))


async def process(conn: AsyncConnection, withdrawal_id: UUID, admin_id: UUID, action: str, reason: str | None) -> None:
    await conn.execute(
        "select private.process_withdrawal(%s, %s, %s, %s)", (withdrawal_id, admin_id, action, reason)
    )


async def get(conn: AsyncConnection, withdrawal_id: UUID) -> dict | None:
    cur = await conn.execute(f"select {WITHDRAWAL_COLUMNS} from public.withdrawals w where w.id = %s", (withdrawal_id,))
    return await cur.fetchone()


async def list_for_user(conn: AsyncConnection, user_id: UUID, limit: int) -> list[dict]:
    cur = await conn.execute(
        f"select {WITHDRAWAL_COLUMNS} from public.withdrawals w where w.user_id = %s "
        "order by w.created_at desc limit %s",
        (user_id, limit),
    )
    return await cur.fetchall()


async def list_for_admin(conn: AsyncConnection, status: str | None, limit: int) -> list[dict]:
    # Les demandes à traiter sont servies de la plus ancienne à la plus récente.
    oldest_first = status in ("pending", "under_review", "approved")
    cur = await conn.execute(
        f"""
        select {WITHDRAWAL_COLUMNS}, p.public_id as client_id, p.first_name || ' ' || p.last_name as client_name,
               p.phone as client_phone, wa.balance as client_balance
        from public.withdrawals w
        join public.profiles p on p.id = w.user_id
        join public.wallets wa on wa.id = w.wallet_id
        where (%(status)s::public.withdrawal_status is null or w.status = %(status)s::public.withdrawal_status)
        order by w.created_at {'asc' if oldest_first else 'desc'}
        limit %(limit)s
        """,
        {"status": status, "limit": limit},
    )
    return await cur.fetchall()
