from psycopg import AsyncConnection


async def public_settings(conn: AsyncConnection) -> dict:
    cur = await conn.execute("select key, value from public.app_settings where is_public order by key")
    return {row["key"]: row["value"] for row in await cur.fetchall()}
