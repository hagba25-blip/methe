from uuid import UUID

from psycopg import AsyncConnection


async def get_profile_with_wallet(conn: AsyncConnection, user_id: UUID) -> dict | None:
    cur = await conn.execute(
        """
        select p.id, p.public_id, p.first_name, p.last_name, p.phone, p.email,
               p.country_code, p.language_code, p.currency_code, p.avatar_url,
               p.status, p.kyc_status, p.created_at,
               w.balance, c.decimals as currency_decimals,
               exists (select 1 from public.admin_users a
                       where a.user_id = p.id and a.is_active) as is_staff
        from public.profiles p
        join public.wallets w on w.user_id = p.id and w.currency_code = p.currency_code
        join public.currencies c on c.code = p.currency_code
        where p.id = %s
        """,
        (user_id,),
    )
    return await cur.fetchone()


async def touch_last_login(conn: AsyncConnection, user_id: UUID) -> None:
    await conn.execute("update public.profiles set last_login_at = now() where id = %s", (user_id,))
