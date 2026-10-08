"""Limitation de débit simple (fenêtre glissante d'une minute, en mémoire).

Suffisant pour un seul processus. En production multi-instances, remplacer le
stockage par Redis (phase 13) sans changer l'interface.
"""

import time
from collections import defaultdict, deque

from fastapi import Request, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, per_minute: int):
        super().__init__(app)
        self.per_minute = per_minute
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def _key(self, request: Request) -> str:
        forwarded = request.headers.get("x-forwarded-for")
        ip = forwarded.split(",")[0].strip() if forwarded else (request.client.host if request.client else "?")
        return ip

    async def dispatch(self, request: Request, call_next):
        now = time.monotonic()
        hits = self._hits[self._key(request)]
        while hits and now - hits[0] > 60:
            hits.popleft()
        if len(hits) >= self.per_minute:
            return JSONResponse(
                {"detail": "Trop de requêtes, réessayez dans un instant"},
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            )
        hits.append(now)
        return await call_next(request)

