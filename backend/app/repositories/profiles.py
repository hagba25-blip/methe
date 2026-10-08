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


EDITABLE_FIELDS = ("first_name", "last_name", "language_code", "avatar_url")


async def update_profile(conn: AsyncConnection, user_id: UUID, changes: dict) -> None:
    fields = [f for f in EDITABLE_FIELDS if f in changes]
    if not fields:
        return
    assignments = ", ".join(f"{f} = %({f})s" for f in fields)  # noms issus d'une liste fixe
    await conn.execute(
        f"update public.profiles set {assignments} where id = %(id)s",
        {**{f: changes[f] for f in fields}, "id": user_id},
    )


async def language_exists(conn: AsyncConnection, code: str) -> bool:
    cur = await conn.execute("select 1 from public.languages where code = %s and is_active", (code,))
    return await cur.fetchone() is not None


async def admin_lookup_by_public_id(conn: AsyncConnection, public_id: str) -> dict | None:
    """Fiche client pour le support / l'administration (cahier des charges §30)."""
    cur = await conn.execute(
        """
        select p.id, p.public_id, p.first_name, p.last_name, p.phone, p.email,
               p.country_code, p.currency_code, p.status, p.kyc_status,
               p.created_at, p.last_login_at,
               w.balance, c.decimals as currency_decimals,
               coalesce(b.bet_count, 0)      as bet_count,
               coalesce(b.total_staked, 0)   as total_staked,
               coalesce(b.total_won, 0)      as total_won,
               coalesce(d.total_deposited, 0) as total_deposited,
               coalesce(x.total_withdrawn, 0) as total_withdrawn
        from public.profiles p
        join public.wallets w on w.user_id = p.id and w.currency_code = p.currency_code
        join public.currencies c on c.code = p.currency_code
        left join lateral (
          select count(*) as bet_count, sum(stake) as total_staked, sum(actual_payout) as total_won
          from public.bets where user_id = p.id
        ) b on true
        left join lateral (
          select sum(amount) as total_deposited from public.deposits
          where user_id = p.id and status = 'approved'
        ) d on true
        left join lateral (
          select sum(net_amount) as total_withdrawn from public.withdrawals
          where user_id = p.id and status = 'paid'
        ) x on true
        where p.public_id = %s
        """,
        (public_id,),
    )
    return await cur.fetchone()
