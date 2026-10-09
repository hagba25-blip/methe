"""Connexion en deux étapes : vérification du mot de passe et défis du code e-mail (schéma private)."""

from uuid import UUID

from psycopg import AsyncConnection


async def start(conn: AsyncConnection, identifier: str, password: str, ip: str | None) -> dict:
    cur = await conn.execute("select * from private.start_login(%s, %s, %s)", (identifier, password, ip))
    return await cur.fetchone()


async def use_challenge(conn: AsyncConnection, challenge_id: UUID) -> str | None:
    """Compte un essai de code ; renvoie l'e-mail si le défi est encore valable."""
    cur = await conn.execute("select private.use_login_challenge(%s) as email", (challenge_id,))
    return (await cur.fetchone())["email"]


async def pending_email(conn: AsyncConnection, challenge_id: UUID) -> str | None:
    cur = await conn.execute(
        "select email from private.login_challenges"
        " where id = %s and consumed_at is null and expires_at > now() and attempts < 5",
        (challenge_id,))
    row = await cur.fetchone()
    return row["email"] if row else None


async def finish(conn: AsyncConnection, challenge_id: UUID) -> None:
    await conn.execute("select private.finish_login_challenge(%s)", (challenge_id,))
