"""Phase 3 : dépôts via agents WhatsApp et validation par l'administration.

Base locale préparée par supabase/tests/run_local.sh : A a 10 000 F,
D (admin@example.com) a le rôle « finance », B n'a aucun rôle.
"""

import os
from urllib.parse import unquote

import pytest
from fastapi.testclient import TestClient

from main import create_app
from tests.test_api import USER_A, token
from tests.test_phase2 import USER_B, auth, public_id_of, sql  # noqa: F401  (fixture)

ADMIN_D = "00000000-0000-0000-0000-00000000000d"

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


@pytest.fixture
def client():
    with TestClient(create_app()) as c:
        yield c


def agent_id(client, number="+22899315092") -> str:
    return next(a["id"] for a in client.get("/v1/agents").json() if a["whatsapp_number"] == number)


def balance(client, user=USER_A) -> int:
    return client.get("/v1/wallet", headers=auth(user)).json()["balance"]


def test_agents_are_public(client):
    numbers = {a["whatsapp_number"] for a in client.get("/v1/agents").json()}
    assert {"+22899315092", "+22891962246"} <= numbers


def test_deposit_request_then_admin_approval(client, sql):
    start = balance(client)
    r = client.post("/v1/deposits", headers=auth(USER_A), json={"agent_id": agent_id(client), "amount": 5000})
    assert r.status_code == 201, r.text
    body = r.json()
    pid = public_id_of(sql, USER_A)
    assert body["deposit"]["status"] == "pending"
    assert body["whatsapp_url"].startswith("https://wa.me/22899315092?text=")
    assert unquote(body["whatsapp_url"].split("text=")[1]) == \
        f"Je veux faire dépôt sur mon compte avec ID du client : {pid}"
    assert balance(client) == start, "ouvrir WhatsApp ne crédite pas le compte"

    dep_id = body["deposit"]["id"]
    assert client.post(f"/v1/admin/deposits/{dep_id}/approve", headers=auth(USER_B), json={}).status_code == 403

    pending = client.get("/v1/admin/deposits", headers=auth(ADMIN_D)).json()
    assert any(d["id"] == dep_id and d["client_id"] == pid for d in pending)

    r = client.post(f"/v1/admin/deposits/{dep_id}/approve", headers=auth(ADMIN_D), json={})
    assert r.status_code == 200, r.text
    assert (r.json()["balance_before"], r.json()["balance_after"]) == (start, start + 5000)
    assert balance(client) == start + 5000

    again = client.post(f"/v1/admin/deposits/{dep_id}/approve", headers=auth(ADMIN_D), json={})
    assert again.status_code == 409 and balance(client) == start + 5000

    mine = client.get("/v1/deposits", headers=auth(USER_A)).json()
    assert mine[0]["status"] == "approved"


def test_reject_and_cancel(client):
    a = agent_id(client, "+22891962246")
    dep = client.post("/v1/deposits", headers=auth(USER_A), json={"agent_id": a, "amount": 1000}).json()["deposit"]
    assert client.post(f"/v1/admin/deposits/{dep['id']}/reject", headers=auth(ADMIN_D), json={"reason": ""}).status_code == 422
    r = client.post(f"/v1/admin/deposits/{dep['id']}/reject", headers=auth(ADMIN_D), json={"reason": "Paiement non reçu"})
    assert r.json()["status"] == "rejected"

    dep = client.post("/v1/deposits", headers=auth(USER_A), json={"agent_id": a, "amount": 1000}).json()["deposit"]
    assert client.post(f"/v1/deposits/{dep['id']}/cancel", headers=auth(USER_A)).json()["status"] == "cancelled"
    assert client.post(f"/v1/deposits/{dep['id']}/cancel", headers=auth(USER_A)).status_code == 409
    # B ne peut pas annuler le dépôt de A
    dep = client.post("/v1/deposits", headers=auth(USER_A), json={"agent_id": a, "amount": 1000}).json()["deposit"]
    assert client.post(f"/v1/deposits/{dep['id']}/cancel", headers=auth(USER_B)).status_code == 404


def test_deposit_below_minimum(client):
    r = client.post("/v1/deposits", headers=auth(USER_A), json={"agent_id": agent_id(client), "amount": 20})
    assert r.status_code == 409 and "hors limites" in r.json()["detail"]


def test_manual_credit_is_idempotent(client, sql):
    pid = public_id_of(sql, USER_A)
    start = balance(client)
    headers = {**auth(ADMIN_D), "Idempotency-Key": "credit-test-0001"}
    body = {"amount": 10000, "reason": "Validation dépôt"}
    r1 = client.post(f"/v1/admin/users/{pid}/credit", headers=headers, json=body)
    r2 = client.post(f"/v1/admin/users/{pid}/credit", headers=headers, json=body)
    assert r1.status_code == r2.status_code == 200, r1.text
    assert r1.json()["balance_after"] == r2.json()["balance_after"] == start + 10000
    assert balance(client) == start + 10000
    assert client.post(f"/v1/admin/users/{pid}/credit", headers=auth(ADMIN_D), json=body).status_code == 422
    assert client.post(f"/v1/admin/users/{pid}/credit", headers={**auth(USER_B), "Idempotency-Key": "x" * 10},
                       json=body).status_code == 403
