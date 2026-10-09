"""Phase 14 : connexion par ID client + mot de passe, puis code envoyé par e-mail."""

import os
import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.security.auth import email_code_verified
from app.services import supabase_auth
from app.services.supabase_auth import CodeError
from main import create_app
from tests.test_api import SECRET, USER_A
from tests.test_phase2 import sql  # noqa: F401  (fixture)

USER_L = "00000000-0000-0000-0000-0000000000c1"
PASSWORD = "Mot-De-Passe-2026"
needs_db = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


def settings(**changes) -> Settings:
    return get_settings().model_copy(update={"supabase_url": "https://exemple.supabase.co",
                                             "supabase_publishable_key": "sb_publishable_test", **changes})


@pytest.fixture
def client():
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings()
    with TestClient(app) as c:
        yield c


@pytest.fixture
def mail(monkeypatch):
    """Remplace Supabase Auth : garde les codes « envoyés » et accepte 123456."""
    sent: list[str] = []

    async def send_code(_settings, email):
        sent.append(email)

    async def verify_code(_settings, email, code):
        if code != "123456":
            raise CodeError("invalid")
        return {"access_token": f"jeton-{email}", "refresh_token": "rafraichir", "expires_in": 3600}

    monkeypatch.setattr(supabase_auth, "send_code", send_code)
    monkeypatch.setattr(supabase_auth, "verify_code", verify_code)
    return sent


@pytest.fixture
def player(sql):
    sql.execute("delete from private.login_attempts where user_id = %s", (USER_L,))
    sql.execute(
        "insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values (%s, %s,"
        " extensions.crypt(%s, extensions.gen_salt('bf')), %s) on conflict (id) do nothing",
        (USER_L, "lina.connexion@example.com", PASSWORD,
         '{"first_name":"Lina","last_name":"C","phone":"+22890000201","country_code":"TG","language_code":"fr",'
         '"currency_code":"XOF","accept_terms":true,"accept_privacy":true}'))
    return sql.execute("select public_id from public.profiles where id = %s", (USER_L,)).fetchone()[0]


def test_email_code_verified():
    assert email_code_verified({"amr": [{"method": "otp", "timestamp": 1}]})
    assert email_code_verified({"amr": [{"method": "password"}, {"method": "email/signup"}]})
    assert not email_code_verified({"amr": [{"method": "password", "timestamp": 1}]})
    assert not email_code_verified({})
    assert not email_code_verified({"amr": "otp"})


def _token(amr: list | None) -> dict:
    claims = {"sub": USER_A, "aud": "authenticated", "exp": int(time.time()) + 600, "role": "authenticated"}
    if amr is not None:
        claims["amr"] = amr
    return {"Authorization": f"Bearer {jwt.encode(claims, SECRET, algorithm='HS256')}"}


@needs_db
def test_password_only_session_is_refused():
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings(require_email_code=True)
    with TestClient(app) as c:
        r = c.get("/v1/me", headers=_token([{"method": "password", "timestamp": 1}]))
        assert r.status_code == 401 and "Code de vérification" in r.json()["detail"]
        assert c.get("/v1/me", headers=_token(None)).status_code == 401
        assert c.get("/v1/me", headers=_token([{"method": "otp", "timestamp": 1}])).status_code == 200


@needs_db
def test_login_with_client_id_and_email_code(client, mail, player):
    r = client.post("/v1/auth/login", json={"identifier": player, "password": PASSWORD})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["email_hint"] == "li*****@example.com" and body["expires_in"] == 600 and body["notice"] is None
    assert mail == ["lina.connexion@example.com"]

    r = client.post("/v1/auth/login/verify", json={"challenge_id": body["challenge_id"], "code": "123456"})
    assert r.status_code == 200, r.text
    assert r.json() == {"access_token": "jeton-lina.connexion@example.com", "refresh_token": "rafraichir",
                        "expires_in": 3600}
    # Un code déjà utilisé ne rouvre pas de session
    r = client.post("/v1/auth/login/verify", json={"challenge_id": body["challenge_id"], "code": "123456"})
    assert r.status_code == 410


@needs_db
def test_login_by_email_and_resend(client, mail, player):
    r = client.post("/v1/auth/login", json={"identifier": " Lina.Connexion@example.com ", "password": PASSWORD})
    assert r.status_code == 200, r.text
    challenge = r.json()["challenge_id"]
    r = client.post("/v1/auth/login/resend", json={"challenge_id": challenge})
    assert r.status_code == 200 and len(mail) == 2


@needs_db
def test_wrong_code_counts_attempts(client, mail, player):
    challenge = client.post("/v1/auth/login", json={"identifier": player, "password": PASSWORD}).json()["challenge_id"]
    for _ in range(5):
        r = client.post("/v1/auth/login/verify", json={"challenge_id": challenge, "code": "000000"})
        assert r.status_code == 400 and r.json()["detail"] == "Code incorrect ou expiré"
    r = client.post("/v1/auth/login/verify", json={"challenge_id": challenge, "code": "123456"})
    assert r.status_code == 410, "après 5 codes faux, il faut recommencer"
    assert client.post("/v1/auth/login/verify", json={"challenge_id": challenge, "code": "12ab"}).status_code == 422


@needs_db
def test_wrong_password_then_lock(client, mail, player):
    for _ in range(5):
        r = client.post("/v1/auth/login", json={"identifier": player, "password": "faux"})
        assert r.status_code == 401 and r.json()["detail"] == "ID client ou mot de passe incorrect"
    r = client.post("/v1/auth/login", json={"identifier": player, "password": PASSWORD})
    assert r.status_code == 429
    assert mail == [], "aucun code envoyé sans le bon mot de passe"
    r = client.post("/v1/auth/login", json={"identifier": "6999999999", "password": PASSWORD})
    assert r.status_code == 401, "ID inconnu : même message"


@needs_db
def test_supabase_asks_to_wait(client, monkeypatch, player):
    async def busy(_settings, _email):
        raise CodeError("rate_limited")

    monkeypatch.setattr(supabase_auth, "send_code", busy)
    r = client.post("/v1/auth/login", json={"identifier": player, "password": PASSWORD})
    assert r.status_code == 200 and "dernier code" in r.json()["notice"]

    async def down(_settings, _email):
        raise CodeError("unavailable")

    monkeypatch.setattr(supabase_auth, "send_code", down)
    r = client.post("/v1/auth/login", json={"identifier": player, "password": PASSWORD})
    assert r.status_code == 502


def test_not_configured():
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings(supabase_publishable_key="")
    with TestClient(app) as c:
        r = c.post("/v1/auth/login", json={"identifier": "6000000001", "password": "x"})
        assert r.status_code == 503


def test_mask_email():
    assert supabase_auth.mask_email("ab@x.tg") == "ab*****@x.tg"
    assert supabase_auth.mask_email("jean.dupont@gmail.com") == "je*****@gmail.com"


def test_supabase_calls(monkeypatch):
    """Requêtes envoyées à Supabase Auth et traduction de ses réponses."""
    import asyncio

    import httpx

    calls: list[tuple[str, dict, str]] = []
    replies = {"/auth/v1/otp": httpx.Response(200, json={}),
               "/auth/v1/verify": httpx.Response(200, json={"access_token": "a", "refresh_token": "r"})}

    def handler(request: httpx.Request) -> httpx.Response:
        import json
        calls.append((request.url.path, json.loads(request.content), request.headers["apikey"]))
        return replies[request.url.path]

    real_client = supabase_auth._client
    monkeypatch.setattr(supabase_auth, "_client", lambda s: httpx.AsyncClient(
        transport=httpx.MockTransport(handler), base_url=str(real_client(s).base_url), headers={"apikey": "cle"}))
    s = settings()
    asyncio.run(supabase_auth.send_code(s, "x@y.tg"))
    assert asyncio.run(supabase_auth.verify_code(s, "x@y.tg", "123456"))["access_token"] == "a"
    assert calls == [("/auth/v1/otp", {"email": "x@y.tg", "create_user": False}, "cle"),
                     ("/auth/v1/verify", {"type": "email", "email": "x@y.tg", "token": "123456"}, "cle")]

    for code, kind in [(429, "rate_limited"), (403, "invalid"), (500, "unavailable")]:
        replies["/auth/v1/verify"] = httpx.Response(code, json={})
        with pytest.raises(CodeError) as e:
            asyncio.run(supabase_auth.verify_code(s, "x@y.tg", "123456"))
        assert e.value.kind == kind
    replies["/auth/v1/otp"] = httpx.Response(500, json={"msg": "Error sending magic link email"})
    with pytest.raises(CodeError) as e:
        asyncio.run(supabase_auth.send_code(s, "x@y.tg"))
    assert e.value.kind == "unavailable"
