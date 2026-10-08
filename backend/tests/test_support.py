"""Phase 11 : support client (après les tests test_phase* et test_risk)."""

import os

import pytest

from tests.test_api import USER_A
from tests.test_phase2 import USER_B, auth, client, sql  # noqa: F401  (fixtures)
from tests.test_phase3 import ADMIN_D
from tests.test_phase5 import USER_E

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


def test_help_center_faq_and_contact(client, sql):
    r = client.get("/v1/support/help", headers=auth(USER_A))
    assert r.status_code == 200
    body = r.json()
    assert len(body["faq"]) >= 10 and body["faq"][0]["category"] == "account"
    assert body["contact"] == {"whatsapp_url": None, "hours": "Tous les jours, 8 h – 22 h"}
    sql.execute("update public.app_settings set value = '\"+228 90 00 00 99\"' where key = 'support.whatsapp_number'")
    try:
        pid = sql.execute("select public_id from public.profiles where id = %s", (USER_A,)).fetchone()[0]
        url = client.get("/v1/support/help", headers=auth(USER_A)).json()["contact"]["whatsapp_url"]
        assert url.startswith("https://wa.me/22890000099?text=") and pid in url
    finally:
        sql.execute("update public.app_settings set value = 'null' where key = 'support.whatsapp_number'")
    assert client.get("/v1/support/help").status_code == 401


def test_ticket_conversation(client, sql):
    r = client.post("/v1/support/tickets", headers=auth(USER_A), json={
        "category": "withdrawal", "subject": "Retrait en attente", "message": "Mon retrait n'est pas arrivé.",
        "related_reference": "wdr-20261008-000001"})
    assert r.status_code == 201, r.text
    t = r.json()
    assert t["reference"].startswith("SUP-") and t["status"] == "open" and t["related_reference"] == "WDR-20261008-000001"
    assert [m["author_name"] for m in t["messages"]] == ["Hubert"]
    assert t["client_id"] is None, "le joueur ne reçoit pas les champs de l'équipe"

    # B ne voit pas la demande de A
    assert client.get(f"/v1/support/tickets/{t['id']}", headers=auth(USER_B)).status_code == 404
    assert client.post(f"/v1/support/tickets/{t['id']}/messages", headers=auth(USER_B),
                       json={"body": "intrus"}).status_code == 404
    # Un joueur sans rôle n'accède pas à la file de l'équipe
    assert client.get("/v1/admin/support/tickets", headers=auth(USER_B)).status_code == 403

    queue = client.get("/v1/admin/support/tickets", headers=auth(ADMIN_D)).json()
    row = next(q for q in queue if q["id"] == t["id"])
    assert row["unread"] == 1 and row["client_name"].startswith("Hubert")

    r = client.post(f"/v1/admin/support/tickets/{t['id']}/messages", headers=auth(ADMIN_D),
                    json={"body": "Le paiement part aujourd'hui."})
    assert r.status_code == 200 and r.json()["status"] == "answered" and r.json()["unread"] == 0
    assert r.json()["assigned_name"] is not None

    mine = client.get("/v1/support/tickets", headers=auth(USER_A)).json()
    assert next(m for m in mine if m["id"] == t["id"])["unread"] == 1
    detail = client.get(f"/v1/support/tickets/{t['id']}", headers=auth(USER_A)).json()
    assert detail["messages"][-1]["author_name"].startswith("Support · ") and detail["messages"][-1]["is_staff"]
    assert next(m for m in client.get("/v1/support/tickets", headers=auth(USER_A)).json()
                if m["id"] == t["id"])["unread"] == 0, "lu à l'ouverture"
    assert sql.execute("select count(*) from public.notifications where user_id = %s and type = 'support_reply'",
                       (USER_A,)).fetchone()[0] >= 1

    r = client.post(f"/v1/admin/support/tickets/{t['id']}/status", headers=auth(ADMIN_D), json={"status": "resolved"})
    assert r.json()["status"] == "resolved"
    assert client.get("/v1/admin/support/tickets?state=done", headers=auth(ADMIN_D)).json()[0]["id"] == t["id"]
    r = client.post(f"/v1/support/tickets/{t['id']}/messages", headers=auth(USER_A), json={"body": "Merci, reçu !"})
    assert r.json()["status"] == "open", "répondre rouvre la demande"
    r = client.post(f"/v1/support/tickets/{t['id']}/close", headers=auth(USER_A))
    assert r.json()["status"] == "closed"
    r = client.post(f"/v1/support/tickets/{t['id']}/messages", headers=auth(USER_A), json={"body": "Encore"})
    assert r.status_code == 409 and "fermée" in r.json()["detail"]
    assert client.post("/v1/support/tickets", headers=auth(USER_A), json={
        "category": "casino", "subject": "x", "message": ""}).status_code == 422


def test_dashboard_support_counts(client, sql):
    sql.execute("select private.grant_staff_role('yao@example.com', 'admin')")
    client.post("/v1/support/tickets", headers=auth(USER_B), json={
        "category": "account", "subject": "Changer de numéro", "message": "J'ai un nouveau numéro."})
    d = client.get("/v1/admin/dashboard", headers=auth(USER_E)).json()
    assert d["support"]["todo_count"] >= 1 and d["support"]["oldest_todo_hours"] >= 0


def test_faq_admin_roles(client, sql):
    new = {"category": "games", "question": "Quand ont lieu les tirages ?", "answer": "Toutes les heures.",
           "is_published": False}
    assert client.post("/v1/admin/faq", headers=auth(ADMIN_D), json=new).status_code == 403, "finance ne rédige pas"
    r = client.post("/v1/admin/faq", headers=auth(USER_E), json=new)
    assert r.status_code == 201
    fid = r.json()["id"]
    assert all(f["id"] != fid for f in client.get("/v1/support/help", headers=auth(USER_A)).json()["faq"]), "brouillon"
    r = client.patch(f"/v1/admin/faq/{fid}", headers=auth(USER_E), json={"is_published": True, "answer": "  Fruits : chaque heure.  "})
    assert r.json()["is_published"] and r.json()["answer"] == "Fruits : chaque heure."
    assert any(f["id"] == fid for f in client.get("/v1/support/help", headers=auth(USER_A)).json()["faq"])
    assert any(f["id"] == fid for f in client.get("/v1/admin/faq", headers=auth(ADMIN_D)).json())
    assert client.delete(f"/v1/admin/faq/{fid}", headers=auth(USER_E)).status_code == 204
    assert client.delete(f"/v1/admin/faq/{fid}", headers=auth(USER_E)).status_code == 404
