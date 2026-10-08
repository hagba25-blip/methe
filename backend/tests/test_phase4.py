"""Phase 4 : retraits (blocage du montant, cycle de statuts, refus et annulation)."""

import os
import uuid

import pytest
from fastapi.testclient import TestClient

from main import create_app
from tests.test_api import USER_A
from tests.test_phase2 import USER_B, auth, sql  # noqa: F401  (fixture)
from tests.test_phase3 import ADMIN_D, balance

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


@pytest.fixture
def client():
    with TestClient(create_app()) as c:
        yield c


def ask(client, amount, key=None, method="mobile_money", account="+22890000001"):
    return client.post(
        "/v1/withdrawals",
        headers={**auth(USER_A), "Idempotency-Key": key or uuid.uuid4().hex},
        json={"amount": amount, "method": method, "payout_account": account},
    )


def test_info(client):
    info = client.get("/v1/withdrawals/info", headers=auth(USER_A)).json()
    assert info["currency_code"] == "XOF" and info["min_amount"] == 1000
    assert info["default_payout_account"] == "+22890000001"
    assert info["can_withdraw"] is True


def test_full_cycle_with_hold(client):
    start = balance(client)
    key = uuid.uuid4().hex
    r = ask(client, 2000, key)
    assert r.status_code == 201, r.text
    wdr = r.json()
    assert wdr["status"] == "pending" and wdr["net_amount"] == 2000
    assert balance(client) == start - 2000, "le montant est bloqué dès la demande"

    assert ask(client, 2000, key).json()["id"] == wdr["id"], "double envoi = même demande"
    assert balance(client) == start - 2000

    blocked = ask(client, 1000)
    assert blocked.status_code == 409 and "déjà en cours" in blocked.json()["detail"]
    assert client.get("/v1/withdrawals/info", headers=auth(USER_A)).json()["can_withdraw"] is False

    url = f"/v1/admin/withdrawals/{wdr['id']}"
    assert client.post(f"{url}/approve", headers=auth(USER_B)).status_code == 403
    assert client.post(f"{url}/pay", headers=auth(ADMIN_D)).status_code == 409, "payer avant approbation"
    queue = client.get("/v1/admin/withdrawals", headers=auth(ADMIN_D)).json()
    assert any(w["id"] == wdr["id"] and w["client_balance"] == start - 2000 for w in queue)

    for action, expected in (("review", "under_review"), ("approve", "approved"), ("pay", "paid")):
        r = client.post(f"{url}/{action}", headers=auth(ADMIN_D))
        assert r.status_code == 200 and r.json()["status"] == expected, r.text
    assert client.post(f"{url}/pay", headers=auth(ADMIN_D)).status_code == 409
    assert balance(client) == start - 2000

    paid = client.get("/v1/admin/withdrawals?status=paid", headers=auth(ADMIN_D)).json()
    assert paid[0]["id"] == wdr["id"]


def test_reject_refunds_and_cancel(client):
    start = balance(client)
    wdr = ask(client, 1500).json()
    url = f"/v1/admin/withdrawals/{wdr['id']}/reject"
    assert client.post(url, headers=auth(ADMIN_D), json={}).status_code == 409, "motif obligatoire"
    r = client.post(url, headers=auth(ADMIN_D), json={"reason": "Numéro injoignable"})
    assert r.json()["status"] == "rejected" and r.json()["rejection_reason"] == "Numéro injoignable"
    assert balance(client) == start

    wdr = ask(client, 1000).json()
    assert balance(client) == start - 1000
    r = client.post(f"/v1/withdrawals/{wdr['id']}/cancel", headers=auth(USER_A))
    assert r.json()["status"] == "cancelled" and balance(client) == start
    assert client.post(f"/v1/withdrawals/{wdr['id']}/cancel", headers=auth(USER_B)).status_code == 404

    mine = client.get("/v1/withdrawals", headers=auth(USER_A)).json()
    assert [w["status"] for w in mine[:2]] == ["cancelled", "rejected"]

    txs = client.get("/v1/wallet/transactions?kind=withdrawals", headers=auth(USER_A)).json()["items"]
    assert {t["label"] for t in txs} == {"Retrait", "Retrait annulé (remboursé)"}


def test_validation(client):
    assert ask(client, 500).status_code == 409, "sous le minimum"
    assert ask(client, 10**9).status_code == 409, "solde insuffisant"
    assert ask(client, 1000, account="90000001").status_code == 409, "numéro sans indicatif"
    assert ask(client, 1000, method="crypto").status_code == 422
    r = client.post("/v1/withdrawals", headers=auth(USER_A), json={"amount": 1000, "payout_account": "+22890000001"})
    assert r.status_code == 422, "clé d'idempotence obligatoire"
