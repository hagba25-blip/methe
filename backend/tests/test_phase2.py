"""Phase 2 : profil, portefeuille, historique, recherche admin par ID.

Ces tests utilisent la base locale préparée par supabase/tests/run_local.sh
(utilisateur A crédité de 10 000 F, utilisateur B sans rôle).
"""

import os

import psycopg
import pytest
from fastapi.testclient import TestClient

from main import create_app
from tests.test_api import USER_A, token

USER_B = "00000000-0000-0000-0000-00000000000b"

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


def auth(sub: str) -> dict:
    return {"Authorization": f"Bearer {token(sub)}"}


@pytest.fixture
def client():
    with TestClient(create_app()) as c:
        yield c


@pytest.fixture
def sql():
    with psycopg.connect(os.environ["TEST_DATABASE_URL"], autocommit=True) as conn:
        yield conn


def public_id_of(sql, user_id: str) -> str:
    return sql.execute("select public_id from public.profiles where id = %s", (user_id,)).fetchone()[0]


def test_wallet_balance(client):
    r = client.get("/v1/wallet", headers=auth(USER_A))
    assert r.status_code == 200
    assert r.json() == {"currency_code": "XOF", "currency_decimals": 0, "balance": 10000, "is_frozen": False}


def test_transactions_history_and_filters(client):
    r = client.get("/v1/wallet/transactions", headers=auth(USER_A)).json()
    assert [(t["label"], t["amount"], t["balance_before"], t["balance_after"]) for t in r["items"]] == [
        ("Dépôt", 10000, 0, 10000)]
    assert r["next_cursor"] is None
    assert client.get("/v1/wallet/transactions?kind=bets", headers=auth(USER_A)).json()["items"] == []
    # B ne voit pas les mouvements de A
    assert client.get("/v1/wallet/transactions", headers=auth(USER_B)).json()["items"] == []


def test_update_profile_allowed_fields_only(client, sql):
    before = public_id_of(sql, USER_A)
    r = client.patch("/v1/me", headers=auth(USER_A),
                     json={"first_name": "  Hubert  ", "language_code": "en", "public_id": "6000000000",
                           "balance": 999999})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["first_name"] == "Hubert" and body["language_code"] == "en"
    assert body["public_id"] == before and body["balance"] == 10000


@pytest.mark.parametrize("payload", [
    {"first_name": "   "},
    {"language_code": "zz"},
    {"avatar_url": "http://insecure.example/a.png"},
])
def test_update_profile_rejects_invalid(client, payload):
    assert client.patch("/v1/me", headers=auth(USER_A), json=payload).status_code == 422


def test_admin_lookup_requires_staff_role(client, sql):
    pid = public_id_of(sql, USER_A)
    assert client.get(f"/v1/admin/users/{pid}", headers=auth(USER_B)).status_code == 403

    sql.execute("select private.grant_staff_role('awa@example.com', 'support')")
    r = client.get(f"/v1/admin/users/{pid}", headers=auth(USER_B))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["public_id"] == pid and body["balance"] == 10000 and body["bet_count"] == 0
    logged = sql.execute(
        "select count(*) from public.admin_actions where action = 'view_user' and target_id = %s", (pid,)
    ).fetchone()[0]
    assert logged >= 1

    assert client.get("/v1/admin/users/6000000000", headers=auth(USER_B)).status_code == 404
    assert client.get("/v1/admin/users/123", headers=auth(USER_B)).status_code == 422
    sql.execute("select private.revoke_staff_role('awa@example.com')")
    assert client.get(f"/v1/admin/users/{pid}", headers=auth(USER_B)).status_code == 403


def test_public_settings(client):
    s = client.get("/v1/settings/public").json()
    assert s["betting.min_stake"] == 50 and "withdrawal.min_amount" in s
