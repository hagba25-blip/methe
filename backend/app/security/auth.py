"""Vérification des JWT émis par Supabase Auth.

Le frontend s'authentifie auprès de Supabase et envoie son access token au
backend (`Authorization: Bearer …`). On vérifie signature, expiration et audience ;
les rôles d'administration sont lus en base (admin_users), jamais dans le token.
"""

from dataclasses import dataclass
from functools import lru_cache
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings, get_settings

_bearer = HTTPBearer(auto_error=False)


# Méthodes de connexion qui prouvent l'accès à la boîte e-mail du compte
# (code à usage unique, lien de confirmation d'inscription, de récupération…).
# Une session ouverte avec le mot de passe seul (« password ») est refusée.
EMAIL_PROVEN_METHODS = {"otp", "magiclink", "email/signup", "recovery", "invite", "email_change"}


def email_code_verified(claims: dict) -> bool:
    amr = claims.get("amr")
    if not isinstance(amr, list):
        return False
    return any(isinstance(m, dict) and m.get("method") in EMAIL_PROVEN_METHODS for m in amr)


@dataclass(frozen=True)
class CurrentUser:
    id: UUID
    email: str | None
    claims: dict


@lru_cache
def _jwks_client(url: str) -> jwt.PyJWKClient:
    return jwt.PyJWKClient(url, cache_keys=True)


def decode_token(token: str, settings: Settings) -> dict:
    options = {"require": ["exp", "sub", "aud"]}
    if settings.supabase_jwt_secret:
        return jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience=settings.supabase_jwt_audience,
            options=options,
        )
    signing_key = _jwks_client(settings.jwks_url).get_signing_key_from_jwt(token)
    return jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256", "ES256"],
        audience=settings.supabase_jwt_audience,
        options=options,
    )


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    settings: Settings = Depends(get_settings),
) -> CurrentUser:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Authentification requise")
    try:
        claims = decode_token(credentials.credentials, settings)
        user = CurrentUser(id=UUID(claims["sub"]), email=claims.get("email"), claims=claims)
    except (jwt.PyJWTError, ValueError, KeyError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Jeton invalide ou expiré") from None
    if settings.require_email_code and not email_code_verified(claims):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Code de vérification requis : reconnectez-vous")
    return user
