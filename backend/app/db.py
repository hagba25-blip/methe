"""Pool de connexions PostgreSQL.

Le backend se connecte directement à la base Supabase avec un rôle privilégié :
c'est lui qui applique les règles métier, puis délègue les écritures financières
aux fonctions SQL (private.post_journal) qui garantissent l'équilibre du ledger.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from uuid import UUID

from psycopg import AsyncConnection
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from app.config import get_settings

_pool: AsyncConnectionPool | None = None


async def open_pool() -> None:
    global _pool
    settings = get_settings()
    if not settings.database_url:
        return
    _pool = AsyncConnectionPool(
        settings.database_url,
        min_size=1,
        max_size=10,
        kwargs={"row_factory": dict_row, "autocommit": False},
        open=False,
    )
    await _pool.open()


async def close_pool() -> None:
    if _pool is not None:
        await _pool.close()


@asynccontextmanager
async def transaction(actor_id: UUID | None = None) -> AsyncIterator[AsyncConnection]:
    """Transaction unique ; `actor_id` alimente audit_logs.actor_id."""
    if _pool is None:
        raise RuntimeError("DATABASE_URL non configurée")
    async with _pool.connection() as conn:
        async with conn.transaction():
            if actor_id is not None:
                await conn.execute(
                    "select set_config('methe.actor_id', %s, true)", (str(actor_id),)
                )
            yield conn
