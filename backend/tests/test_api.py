import os
import time

import jwt
import pytest
from fastapi.testclient import TestClient

from main import create_app

SECRET = os.environ["SUPABASE_JWT_SECRET"]
USER_A = "00000000-0000-0000-0000-00000000000a"


def token(sub: str, secret: str = SECRET, exp_offset: int = 3600) -> str:
    return jwt.encode(
        {"sub": sub, "aud": "authenticated", "exp": int(time.time()) + exp_offset, "role": "authenticated"},
        secret, algorithm="HS256")


@pytest.fixture
def client():
    with TestClient(create_app()) as c:
        yield c


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


@pytest.mark.parametrize("headers", [
    {},
    {"Authorization": "Bearer pas-un-jwt"},
    {"Authorization": f"Bearer {token(USER_A, secret='mauvais-secret-mauvais-secret-32')}"},
    {"Authorization": f"Bearer {token(USER_A, exp_offset=-10)}"},
])
def test_me_rejects_bad_tokens(client, headers):
    assert client.get("/v1/me", headers=headers).status_code == 401


needs_db = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


@needs_db
def test_me_returns_profile_and_balance(client):
    r = client.get("/v1/me", headers={"Authorization": f"Bearer {token(USER_A)}"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["public_id"].startswith("6") and len(body["public_id"]) == 10
    assert body["currency_code"] == "XOF" and body["balance"] == 10000


@needs_db
def test_locale_detect(client):
    r = client.get("/v1/locale/detect", headers={"cf-ipcountry": "CI"})
    assert r.json()["dial_code"] == "+225"


@pytest.mark.parametrize("method", ["GET", "POST", "PATCH", "DELETE"])
def test_cors_preflight_allows_app_methods(client, method):
    """L'application Web (autre domaine) doit pouvoir appeler toutes les méthodes utilisées."""
    r = client.options("/v1/admin/faq/1", headers={
        "Origin": "http://localhost:5000", "Access-Control-Request-Method": method,
        "Access-Control-Request-Headers": "authorization,content-type"})
    assert r.status_code == 200, r.text
    assert method in r.headers["access-control-allow-methods"]
    assert r.headers["access-control-allow-origin"] == "http://localhost:5000"
