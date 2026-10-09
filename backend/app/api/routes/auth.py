"""Connexion : ID client (ou e-mail) + mot de passe, puis code envoyé à l'e-mail du compte."""

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app import db
from app.config import Settings, get_settings
from app.repositories import login
from app.schemas.auth import LoginChallenge, LoginResend, LoginSession, LoginStart, LoginVerify
from app.security.rate_limit import client_ip
from app.services import supabase_auth
from app.services.supabase_auth import CodeError

router = APIRouter(prefix="/v1/auth", tags=["auth"])

CHALLENGE_SECONDS = 600
RESEND_NOTICE = "Un code vient déjà d'être envoyé : utilisez le dernier code reçu, ou redemandez-en un dans une minute."
SEND_FAILED = "L'envoi de l'e-mail a échoué : réessayez dans un instant ou contactez le support."


def _configured(settings: Settings = Depends(get_settings)) -> Settings:
    if not settings.supabase_url or not settings.supabase_publishable_key:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Connexion par code non configurée sur le serveur")
    return settings


async def _send(settings: Settings, email: str) -> str | None:
    """Envoie le code ; renvoie un avertissement si Supabase demande d'attendre."""
    try:
        await supabase_auth.send_code(settings, email)
    except CodeError as e:
        if e.kind == "rate_limited":
            return RESEND_NOTICE
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, SEND_FAILED) from None
    return None


@router.post("/login", response_model=LoginChallenge)
async def start_login(body: LoginStart, request: Request, settings: Settings = Depends(_configured)) -> LoginChallenge:
    """Étape 1 : vérifie l'identifiant et le mot de passe, puis envoie le code par e-mail."""
    ip = client_ip(request, settings.trusted_proxy_hops)
    async with db.transaction() as conn:
        row = await login.start(conn, body.identifier, body.password, ip)
    if row["status"] == "locked":
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS,
                            "Trop d'essais : réessayez dans 15 minutes ou contactez le support")
    if row["status"] == "inactive":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Ce compte ne peut pas se connecter : contactez le support")
    if row["status"] != "ok":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "ID client ou mot de passe incorrect")
    notice = await _send(settings, row["email"])
    return LoginChallenge(challenge_id=row["challenge_id"], email_hint=supabase_auth.mask_email(row["email"]),
                          expires_in=CHALLENGE_SECONDS, notice=notice)


@router.post("/login/resend", response_model=LoginChallenge)
async def resend_code(body: LoginResend, settings: Settings = Depends(_configured)) -> LoginChallenge:
    async with db.transaction() as conn:
        email = await login.pending_email(conn, body.challenge_id)
    if email is None:
        raise HTTPException(status.HTTP_410_GONE, "Session de connexion expirée : recommencez")
    notice = await _send(settings, email)
    return LoginChallenge(challenge_id=body.challenge_id, email_hint=supabase_auth.mask_email(email),
                          expires_in=CHALLENGE_SECONDS, notice=notice)


@router.post("/login/verify", response_model=LoginSession)
async def verify_login(body: LoginVerify, settings: Settings = Depends(_configured)) -> LoginSession:
    """Étape 2 : vérifie le code reçu par e-mail et ouvre la session."""
    async with db.transaction() as conn:       # l'essai est compté même si le code est faux
        email = await login.use_challenge(conn, body.challenge_id)
    if email is None:
        raise HTTPException(status.HTTP_410_GONE, "Code expiré ou trop d'essais : recommencez la connexion")
    try:
        session = await supabase_auth.verify_code(settings, email, body.code)
    except CodeError as e:
        if e.kind == "invalid":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Code incorrect ou expiré") from None
        if e.kind == "rate_limited":
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Trop d'essais : patientez un instant") from None
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Vérification impossible pour le moment : réessayez") from None
    async with db.transaction() as conn:
        await login.finish(conn, body.challenge_id)
    return LoginSession(access_token=session["access_token"], refresh_token=session["refresh_token"],
                        expires_in=int(session.get("expires_in", 3600)))
