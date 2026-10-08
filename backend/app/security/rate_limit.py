"""Limitation de débit simple (fenêtre glissante d'une minute, en mémoire).

Suffisant pour un seul processus. En production multi-instances, remplacer le
stockage par Redis sans changer l'interface.

L'adresse du client est celle de la connexion. Derrière un proxy (Render,
Fly, Nginx…), régler TRUSTED_PROXY_HOPS sur le nombre de proxys : l'adresse est
alors lue dans X-Forwarded-For en partant de la droite, là où le proxy l'a
ajoutée, et un client ne peut pas contourner la limite en envoyant un faux en-tête.
"""

import time
from collections import defaultdict, deque

from fastapi import Request, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware


def client_ip(request: Request, trusted_hops: int) -> str:
    direct = request.client.host if request.client else "?"
    if trusted_hops <= 0:
        return direct
    chain = [h.strip() for h in request.headers.get("x-forwarded-for", "").split(",") if h.strip()]
    return chain[-trusted_hops] if len(chain) >= trusted_hops else direct


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, per_minute: int, trusted_hops: int = 0):
        super().__init__(app)
        self.per_minute = per_minute
        self.trusted_hops = trusted_hops
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._last_sweep = time.monotonic()

    def _sweep(self, now: float) -> None:
        # Oublie les clients inactifs pour que la mémoire ne grossisse pas indéfiniment.
        if now - self._last_sweep < 60:
            return
        self._last_sweep = now
        for key in [k for k, hits in self._hits.items() if not hits or now - hits[-1] > 60]:
            del self._hits[key]

    async def dispatch(self, request: Request, call_next):
        now = time.monotonic()
        self._sweep(now)
        hits = self._hits[client_ip(request, self.trusted_hops)]
        while hits and now - hits[0] > 60:
            hits.popleft()
        if len(hits) >= self.per_minute:
            return JSONResponse(
                {"detail": "Trop de requêtes, réessayez dans un instant"},
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                headers={"Retry-After": str(max(1, int(61 - (now - hits[0]))))},
            )
        hits.append(now)
        return await call_next(request)
