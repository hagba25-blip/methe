"""Appels à Supabase Auth pour le code de connexion envoyé par e-mail.

Supabase génère le code, l'envoie avec le modèle d'e-mail « Magic Link » (qui doit
contenir {{ .Token }}) et le vérifie. La clé utilisée est la clé publique du projet.
"""

import httpx

from app.config import Settings


class CodeError(Exception):
    """Envoi ou vérification refusés par Supabase Auth."""

    def __init__(self, kind: str):
        super().__init__(kind)
        self.kind = kind  # "rate_limited" | "invalid" | "unavailable"


def _client(settings: Settings) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        base_url=f"{settings.supabase_url.rstrip('/')}/auth/v1",
        headers={"apikey": settings.supabase_publishable_key},
        timeout=15,
    )


async def send_code(settings: Settings, email: str) -> None:
    try:
        async with _client(settings) as http:
            res = await http.post("/otp", json={"email": email, "create_user": False})
    except httpx.HTTPError:
        raise CodeError("unavailable") from None
    if res.status_code == 429:
        raise CodeError("rate_limited")
    if res.status_code >= 400:
        raise CodeError("unavailable")


async def verify_code(settings: Settings, email: str, code: str) -> dict:
    try:
        async with _client(settings) as http:
            res = await http.post("/verify", json={"type": "email", "email": email, "token": code})
    except httpx.HTTPError:
        raise CodeError("unavailable") from None
    if res.status_code == 429:
        raise CodeError("rate_limited")
    if res.status_code in (400, 401, 403, 404, 422):
        raise CodeError("invalid")
    if res.status_code >= 400:
        raise CodeError("unavailable")
    return res.json()


def mask_email(email: str) -> str:
    name, _, domain = email.partition("@")
    return f"{name[:2]}*****@{domain}"
