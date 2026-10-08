"""Indicateurs du tableau de bord administrateur (lecture seule).

Tous les montants sont filtrés sur une devise ; les jours sont découpés en UTC
(= heure de Lomé). Les paris remboursés ou annulés ne comptent pas comme misés.
"""

from datetime import datetime
from uuid import UUID

from psycopg import AsyncConnection


async def overview(conn: AsyncConnection, since: datetime, currency: str) -> dict:
    p = {"since": since, "cur": currency}
    users = await (await conn.execute(
        """
        select count(*) as total,
               count(*) filter (where created_at >= %(since)s) as new_in_period,
               count(*) filter (where last_login_at >= %(since)s) as active_in_period,
               count(*) filter (where status in ('suspended', 'blocked')) as restricted,
               coalesce((select sum(w.balance) from public.wallets w
                          where w.owner_type = 'user' and w.currency_code = %(cur)s), 0)::bigint as balances_total
        from public.profiles
        """, p)).fetchone()

    deposits = await (await conn.execute(
        """
        select count(*) filter (where status = 'pending') as pending_count,
               coalesce(sum(amount) filter (where status = 'pending'), 0)::bigint as pending_amount,
               count(*) filter (where status = 'approved' and reviewed_at >= %(since)s) as approved_count,
               coalesce(sum(amount) filter (where status = 'approved' and reviewed_at >= %(since)s), 0)::bigint
                 as approved_amount
        from public.deposits where currency_code = %(cur)s
        """, p)).fetchone()

    withdrawals = await (await conn.execute(
        """
        select count(*) filter (where status in ('pending', 'under_review', 'approved')) as open_count,
               coalesce(sum(amount) filter (where status in ('pending', 'under_review', 'approved')), 0)::bigint
                 as open_amount,
               count(*) filter (where status = 'paid' and paid_at >= %(since)s) as paid_count,
               coalesce(sum(amount) filter (where status = 'paid' and paid_at >= %(since)s), 0)::bigint as paid_amount
        from public.withdrawals where currency_code = %(cur)s
        """, p)).fetchone()

    games = await (await conn.execute(
        """
        select g.code as game_code, g.name,
               count(b.id) as bet_count,
               count(distinct b.user_id) as players,
               coalesce(sum(b.stake) filter (where b.status in ('pending', 'won', 'lost')), 0)::bigint as staked,
               coalesce(sum(b.stake) filter (where b.status = 'pending'), 0)::bigint as pending_stake,
               coalesce(sum(b.actual_payout) filter (where b.status = 'won'), 0)::bigint as paid
        from public.games g
        left join public.bets b on b.game_code = g.code and b.placed_at >= %(since)s and b.currency_code = %(cur)s
        group by g.code, g.name, g.sort_order order by g.sort_order
        """, p)).fetchall()
    for g in games:
        # Produit brut des jeux : mises réglées − gains versés.
        g["gross_revenue"] = g["staked"] - g["pending_stake"] - g["paid"]

    players = await (await conn.execute(
        "select count(distinct user_id) as n from public.bets where placed_at >= %(since)s and currency_code = %(cur)s",
        p)).fetchone()

    daily = await (await conn.execute(
        """
        with days as (
          select generate_series(date_trunc('day', %(since)s::timestamptz at time zone 'UTC'),
                                 date_trunc('day', now() at time zone 'UTC'), interval '1 day') as d)
        select to_char(d, 'YYYY-MM-DD') as day,
               coalesce((select sum(stake) from public.bets
                          where status in ('pending', 'won', 'lost') and currency_code = %(cur)s
                            and placed_at >= d at time zone 'UTC' and placed_at < (d + interval '1 day') at time zone 'UTC'),
                        0)::bigint as staked,
               coalesce((select sum(actual_payout) from public.bets
                          where status = 'won' and currency_code = %(cur)s
                            and settled_at >= d at time zone 'UTC' and settled_at < (d + interval '1 day') at time zone 'UTC'),
                        0)::bigint as paid,
               coalesce((select sum(amount) from public.deposits
                          where status = 'approved' and currency_code = %(cur)s
                            and reviewed_at >= d at time zone 'UTC' and reviewed_at < (d + interval '1 day') at time zone 'UTC'),
                        0)::bigint as deposits,
               coalesce((select sum(amount) from public.withdrawals
                          where status = 'paid' and currency_code = %(cur)s
                            and paid_at >= d at time zone 'UTC' and paid_at < (d + interval '1 day') at time zone 'UTC'),
                        0)::bigint as withdrawals
        from days order by d
        """, p)).fetchall()

    system = await (await conn.execute(
        "select system_code as code, balance from public.wallets "
        "where owner_type = 'system' and currency_code = %(cur)s order by system_code", p)).fetchall()

    rounds = await (await conn.execute(
        """
        select r.id, r.game_code, r.round_number, r.status::text as status, r.draw_at, r.result,
               count(b.id) as bet_count,
               coalesce(sum(b.stake) filter (where b.status <> 'refunded' and b.status <> 'cancelled'), 0)::bigint
                 as staked,
               coalesce(sum(b.actual_payout), 0)::bigint as paid
        from public.game_rounds r
        left join public.bets b on b.round_id = r.id and b.currency_code = %(cur)s
        where r.status <> 'scheduled' and r.draw_at <= now() + interval '3 hours'
        group by r.id order by r.draw_at desc limit 12
        """, p)).fetchall()

    risk = await (await conn.execute(
        "select count(*) as open_count, count(*) filter (where severity >= 4) as high_count "
        "from public.risk_events where resolved_at is null")).fetchone()

    support = await (await conn.execute(
        """
        select count(*) filter (where status = 'open') as todo_count,
               count(*) filter (where status = 'answered') as answered_count,
               coalesce(extract(epoch from now() - min(last_message_at) filter (where status = 'open')) / 3600, 0)::int
                 as oldest_todo_hours
        from public.support_tickets
        """)).fetchone()

    return {
        "since": since,
        "risk": risk,
        "support": support,
        "currency_code": currency,
        "users": users,
        "deposits": deposits,
        "withdrawals": withdrawals,
        "bets": {
            "bet_count": sum(g["bet_count"] for g in games),
            "players": players["n"],
            "staked": sum(g["staked"] for g in games),
            "pending_stake": sum(g["pending_stake"] for g in games),
            "paid": sum(g["paid"] for g in games),
            "gross_revenue": sum(g["gross_revenue"] for g in games),
        },
        "games": games,
        "daily": daily,
        "system_wallets": system,
        "recent_rounds": rounds,
    }


async def staff_role(conn: AsyncConnection, user_id: UUID) -> str | None:
    row = await (await conn.execute(
        "select role::text as role from public.admin_users where user_id = %s and is_active", (user_id,))).fetchone()
    return row["role"] if row else None


async def admin_actions(conn: AsyncConnection, limit: int, before_id: int | None) -> list[dict]:
    cur = await conn.execute(
        """
        select a.id, a.action, a.target_type, a.target_id, a.reason, a.created_at,
               p.public_id as admin_public_id, p.first_name || ' ' || p.last_name as admin_name
        from public.admin_actions a join public.profiles p on p.id = a.admin_id
        where (%(before)s::bigint is null or a.id < %(before)s)
        order by a.id desc limit %(limit)s
        """,
        {"before": before_id, "limit": limit},
    )
    return await cur.fetchall()
