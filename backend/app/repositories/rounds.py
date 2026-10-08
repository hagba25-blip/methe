from datetime import datetime
from uuid import UUID

from psycopg import AsyncConnection

ROUND_COLUMNS = """
  r.id, r.game_code, r.round_number, r.opens_at, r.closes_at, r.draw_at, r.status::text as status,
  r.commitment_hash, r.revealed_seed, r.algorithm_version, r.result, r.drawn_at, r.published_at
"""


async def upcoming(conn: AsyncConnection, game_code: str) -> list[dict]:
    """Tour ouvert (s'il y en a un) puis tours programmés, du plus proche au plus lointain."""
    cur = await conn.execute(
        f"select {ROUND_COLUMNS} from public.game_rounds r "
        "where r.game_code = %s and r.status in ('scheduled', 'open', 'closed') order by r.draw_at limit 3",
        (game_code,),
    )
    return await cur.fetchall()


async def results(conn: AsyncConnection, game_code: str, limit: int, before: datetime | None) -> list[dict]:
    cur = await conn.execute(
        f"select {ROUND_COLUMNS} from public.game_rounds r "
        "where r.game_code = %s and r.status in ('published', 'settled') "
        "and (%s::timestamptz is null or r.draw_at < %s::timestamptz) order by r.draw_at desc limit %s",
        (game_code, before, before, limit),
    )
    return await cur.fetchall()


async def get(conn: AsyncConnection, round_id: UUID) -> dict | None:
    cur = await conn.execute(f"select {ROUND_COLUMNS} from public.game_rounds r where r.id = %s", (round_id,))
    return await cur.fetchone()


async def fruit_symbols(conn: AsyncConnection) -> list[str]:
    cur = await conn.execute("select code from public.game_symbols where game_code = 'FRUITS'")
    return [row["code"] for row in await cur.fetchall()]


async def engine_tick(conn: AsyncConnection) -> dict:
    cur = await conn.execute("select private.engine_tick() as r")
    return (await cur.fetchone())["r"]


async def cancel(conn: AsyncConnection, round_id: UUID, admin_id: UUID, reason: str) -> None:
    await conn.execute("select private.cancel_round(%s, %s, %s)", (round_id, admin_id, reason))
