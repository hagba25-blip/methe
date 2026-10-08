from psycopg import AsyncConnection

from app.services.locale import Country


async def active_countries(conn: AsyncConnection) -> dict[str, Country]:
    cur = await conn.execute(
        "select code, name, dial_code, default_currency, default_language "
        "from public.countries where is_active order by name"
    )
    return {row["code"]: Country(**row) for row in await cur.fetchall()}


async def active_languages(conn: AsyncConnection) -> set[str]:
    cur = await conn.execute("select code from public.languages where is_active")
    return {row["code"] for row in await cur.fetchall()}
