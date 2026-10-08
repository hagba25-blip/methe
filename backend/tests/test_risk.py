"""Phase 10 : alertes anti-fraude, statut des comptes, protections HTTP (après les tests test_phase*)."""

import os
import uuid

import pytest
from fastapi.testclient import TestClient
from starlette.requests import Request

from main import create_app
from app.security.rate_limit import client_ip
from tests.test_api import USER_A
from tests.test_phase2 import USER_B, auth, sql  # noqa: F401  (fixture)
from tests.test_phase3 import ADMIN_D
from tests.test_phase5 import USER_E
from tests.test_phase6 import bet, client, fruits_round  # noqa: F401  (fixtures)

needs_db = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


def _request(peer: str, forwarded: str | None) -> Request:
    headers = [(b"x-forwarded-for", forwarded.encode())] if forwarded else []
    return Request({"type": "http", "headers": headers, "client": (peer, 1234)})


def test_client_ip_ignores_spoofed_forwarded_for():
    assert client_ip(_request("10.0.0.5", "1.2.3.4"), trusted_hops=0) == "10.0.0.5", "sans proxy : en-tête ignoré"
    # Derrière 1 proxy : l'adresse ajoutée par le proxy (la dernière) fait foi, pas celle envoyée par le client.
    assert client_ip(_request("10.0.0.5", "6.6.6.6, 41.0.0.9"), trusted_hops=1) == "41.0.0.9"
    assert client_ip(_request("10.0.0.5", None), trusted_hops=1) == "10.0.0.5"


def test_rate_limit_and_security_headers():
    os.environ["RATE_LIMIT_PER_MINUTE"] = "3"
    from app.config import get_settings
    get_settings.cache_clear()
    try:
        with TestClient(create_app()) as c:
            codes = [c.get("/health").status_code for _ in range(4)]
            assert codes[:3] == [200, 200, 200] and codes[3] == 429
            r = c.get("/health")
            assert r.headers["retry-after"]
    finally:
        del os.environ["RATE_LIMIT_PER_MINUTE"]
        get_settings.cache_clear()
    with TestClient(create_app()) as c:
        r = c.get("/health")
        assert r.headers["x-content-type-options"] == "nosniff"
        assert r.headers["x-frame-options"] == "DENY" and r.headers["cache-control"] == "no-store"


@needs_db
def test_account_status_blocks_betting(client, sql, fruits_round):
    pid = sql.execute("select public_id from public.profiles where id = %s", (USER_B,)).fetchone()[0]
    sql.execute("select private.grant_staff_role('yao@example.com', 'admin')")
    sql.execute("select private.grant_staff_role('awa@example.com', 'support')")
    body = {"status": "suspended", "reason": "Vérification d'identité"}
    assert client.post(f"/v1/admin/users/{pid}/status", headers=auth(ADMIN_D), json=body).status_code == 403, \
        "finance ne change pas le statut"
    r = client.post(f"/v1/admin/users/{pid}/status", headers=auth(USER_E), json=body)
    assert r.status_code == 409, "B est membre support : réservé au super admin"
    sql.execute("select private.revoke_staff_role('awa@example.com')")

    apid = sql.execute("select public_id from public.profiles where id = %s", (USER_A,)).fetchone()[0]
    r = client.post(f"/v1/admin/users/{apid}/status", headers=auth(USER_E), json={**body, "status": "blocked"})
    assert r.status_code == 200 and r.json()["status"] == "blocked"
    r = bet(client, fruits_round, ["POMME"], 50)
    assert r.status_code == 409 and "bloqué" in r.json()["detail"]
    r = client.post(f"/v1/admin/users/{apid}/status", headers=auth(USER_E), json={"status": "active", "reason": "Levée"})
    assert r.json()["status"] == "active"
    assert bet(client, fruits_round, ["POMME"], 50).status_code == 201
    assert client.post(f"/v1/admin/users/{apid}/status", headers=auth(USER_E),
                       json={"status": "frozen", "reason": "x"}).status_code == 422


@needs_db
def test_risk_events_list_and_resolve(client, sql):
    sql.execute("select private.raise_risk(%s, 'big_win', 2, %s, '{\"payout\": 900000}')", (USER_A, f"BET-{uuid.uuid4().hex[:8]}"))
    events = client.get("/v1/admin/risk-events", headers=auth(ADMIN_D)).json()
    ev = next(e for e in events if e["kind"] == "big_win" and e["details"].get("payout") == 900000)
    assert ev["client_id"] and ev["resolved_at"] is None
    assert client.get("/v1/admin/risk-events", headers=auth(USER_A)).status_code == 403
    assert client.post(f"/v1/admin/risk-events/{ev['id']}/resolve", headers=auth(ADMIN_D), json={"note": ""}).status_code == 422
    r = client.post(f"/v1/admin/risk-events/{ev['id']}/resolve", headers=auth(ADMIN_D), json={"note": "Tirage vérifié"})
    assert r.status_code == 200 and r.json()["resolution_note"] == "Tirage vérifié" and r.json()["resolved_by_name"]
    open_ids = [e["id"] for e in client.get("/v1/admin/risk-events", headers=auth(ADMIN_D)).json()]
    assert ev["id"] not in open_ids
    mine = client.get("/v1/admin/risk-events", headers=auth(ADMIN_D), params={"state": "all", "client_id": ev["client_id"]}).json()
    assert ev["id"] in [e["id"] for e in mine]
    dash = client.get("/v1/admin/dashboard", headers=auth(ADMIN_D)).json()
    assert dash["risk"]["open_count"] >= 0


@needs_db
def test_withdrawal_list_shows_risk_flags(client, sql):
    # Retrait vers le numéro d'un autre joueur : alerte visible dans la file des retraits.
    other_phone = sql.execute("select phone from public.profiles where id = %s", (USER_B,)).fetchone()[0]
    sql.execute("select private.admin_credit((select public_id from public.profiles where id = %s), %s, 5000, 'Test', %s)",
                (USER_A, ADMIN_D, uuid.uuid4().hex))
    r = client.post("/v1/withdrawals", headers={**auth(USER_A), "Idempotency-Key": uuid.uuid4().hex},
                    json={"amount": 1000, "method": "mobile_money", "payout_account": other_phone})
    assert r.status_code == 201, r.text
    queue = client.get("/v1/admin/withdrawals", headers=auth(ADMIN_D)).json()
    w = next(x for x in queue if x["id"] == r.json()["id"])
    assert "shared_payout_account" in w["risk_flags"]
    client.post(f"/v1/withdrawals/{w['id']}/cancel", headers=auth(USER_A))
