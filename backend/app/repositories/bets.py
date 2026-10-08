from uuid import UUID

from psycopg import AsyncConnection

BET_COLUMNS = """
  b.id, b.reference, b.round_id, g.round_number, g.draw_at, g.status::text as round_status, g.result as round_result,
  b.game_code, b.game_type_code, b.selection_count, b.stake, b.currency_code, b.odds_snapshot,
  b.potential_payout, b.status::text as status, b.actual_payout, b.placed_at, b.settled_at,
  array(select i.value from public.bet_items i where i.bet_id = b.id order by i.value) as selections,
  coalesce(r.matched_values, '{}') as matched_values
"""
BET_FROM = """
  from public.bets b
  join public.game_rounds g on g.id = b.round_id
  left join public.bet_results r on r.bet_id = b.id
"""


async def catalog(conn: AsyncConnection) -> list[dict]:
    cur = await conn.execute(
        """
        select g.code, g.name, g.description, ds.interval_minutes, ds.close_before_seconds,
          coalesce((select jsonb_agg(jsonb_build_object(
                      'code', t.code, 'name', t.name, 'min_selection', t.min_selection,
                      'settlement_mode', t.settlement_mode,
                      'commission_percent', case when t.settlement_mode = 'pool'
                                                 then private.setting_numeric('pool.commission_percent', 10) end,
                      'max_selection', t.max_selection,
                      'min_stake', greatest(t.min_stake, private.setting_bigint('betting.min_stake', 50)),
                      'odds', private.playable_odds(t.code)) order by t.sort_order)
                    from public.game_types t where t.game_code = g.code and t.is_active), '[]') as types,
          coalesce((select jsonb_agg(jsonb_build_object('code', s.code, 'label', s.label, 'emoji', s.emoji)
                                     order by s.sort_order)
                    from public.game_symbols s where s.game_code = g.code), '[]') as symbols
        from public.games g left join public.draw_schedules ds on ds.game_code = g.code
        where g.is_active order by g.sort_order
        """
    )
    return await cur.fetchall()


async def place(
    conn: AsyncConnection, user_id: UUID, round_id: UUID, game_type: str, selections: list[str], stake: int, key: str
) -> UUID:
    cur = await conn.execute(
        "select (private.place_bet(%s, %s, %s, %s, %s, %s)).id",
        (user_id, round_id, game_type, selections, stake, key),
    )
    return (await cur.fetchone())["id"]


async def get(conn: AsyncConnection, bet_id: UUID, user_id: UUID) -> dict | None:
    cur = await conn.execute(f"select {BET_COLUMNS} {BET_FROM} where b.id = %s and b.user_id = %s", (bet_id, user_id))
    return await cur.fetchone()


async def list_for_user(
    conn: AsyncConnection, user_id: UUID, statuses: list[str] | None, game: str | None, limit: int, before
) -> list[dict]:
    cur = await conn.execute(
        f"""
        select {BET_COLUMNS} {BET_FROM}
        where b.user_id = %(user)s
          and (%(statuses)s::text[] is null or b.status::text = any(%(statuses)s::text[]))
          and (%(game)s::text is null or b.game_code = %(game)s::text)
          and (%(before)s::timestamptz is null or b.placed_at < %(before)s::timestamptz)
        order by b.placed_at desc limit %(limit)s
        """,
        {"user": user_id, "statuses": statuses, "game": game, "before": before, "limit": limit},
    )
    return await cur.fetchall()


async def pool_state(conn: AsyncConnection, round_id: UUID) -> dict:
    cur = await conn.execute("select private.pool_state(%s) as r", (round_id,))
    return (await cur.fetchone())["r"]
