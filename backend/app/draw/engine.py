"""Battement du moteur de tirage depuis le backend.

Sur Supabase, pg_cron appelle déjà `private.engine_tick()` chaque minute. Cette
boucle sert quand pg_cron n'est pas disponible (DRAW_ENGINE_ENABLED=true).
Plusieurs instances peuvent tourner : la base n'exécute qu'un battement à la fois.
"""

import asyncio
import logging

from app import db
from app.repositories import rounds

log = logging.getLogger("methe.engine")


async def tick() -> dict:
    async with db.transaction() as conn:
        return await rounds.engine_tick(conn)


async def run_forever(interval_seconds: float = 30) -> None:
    while True:
        try:
            result = await tick()
            if any(result.get(k) for k in ("opened", "closed", "drawn", "cancelled_missed")):
                log.info("moteur de tirage : %s", result)
        except Exception:  # le moteur ne doit jamais s'arrêter sur une erreur ponctuelle
            log.exception("battement du moteur en échec")
        await asyncio.sleep(interval_seconds)
