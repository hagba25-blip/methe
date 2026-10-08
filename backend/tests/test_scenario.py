"""Parcours complet d'un nouveau joueur, de l'inscription au retrait payé.

Chaque étape passe par l'API comme le ferait l'application ; l'argent est
recompté à la fin à partir du ledger.
"""

import json
import os
import random
import uuid

import pytest

from tests.test_phase2 import auth, client, sql  # noqa: F401  (fixtures)
from tests.test_phase3 import ADMIN_D, agent_id
from tests.test_phase6 import bet, fruits_round  # noqa: F401  (fixture)

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


@pytest.fixture
def new_player(sql):
    """Inscription : Supabase Auth crée l'utilisateur, le trigger crée profil et portefeuille."""
    uid = str(uuid.uuid4())
    phone = f"+2289{random.randint(1000000, 9999999)}"
    meta = {"first_name": "Kossi", "last_name": "Parcours", "phone": phone, "country_code": "TG",
            "language_code": "fr", "currency_code": "XOF", "accept_terms": True, "accept_privacy": True}
    sql.execute("insert into auth.users (id, email, raw_user_meta_data) values (%s, %s, %s)",
                (uid, f"parcours-{uid[:8]}@example.com", json.dumps(meta)))
    return uid, phone


def wallet(client, user) -> int:
    return client.get("/v1/wallet", headers=auth(user)).json()["balance"]


def test_full_player_journey(client, sql, new_player, fruits_round):
    user, phone = new_player
    h = auth(user)

    # 1. Profil créé à l'inscription, solde à zéro
    me = client.get("/v1/me", headers=h).json()
    assert me["public_id"].startswith("6") and len(me["public_id"]) == 10
    assert me["phone"] == phone and me["currency_code"] == "XOF"
    assert wallet(client, user) == 0

    # 2. Dépôt de 5 000 F via un agent, validé par l'administration
    r = client.post("/v1/deposits", headers=h, json={"agent_id": agent_id(client), "amount": 5000})
    assert r.status_code == 201, r.text
    dep = r.json()["deposit"]
    assert me["public_id"] in r.json()["whatsapp_url"].replace("%20", " ")
    assert wallet(client, user) == 0, "rien n'est crédité avant validation"
    r = client.post(f"/v1/admin/deposits/{dep['id']}/approve", headers=auth(ADMIN_D), json={})
    assert r.status_code == 200, r.text
    assert wallet(client, user) == 5000

    # 3. Deux paris sur le même tirage des Fruits : 20 fruits (gagne toujours) et un seul fruit
    fruits = next(g for g in client.get("/v1/games").json() if g["code"] == "FRUITS")
    sure = bet(client, fruits_round, [f["code"] for f in fruits["symbols"]], 1000, user=user)
    assert sure.status_code == 201, sure.text
    single = bet(client, fruits_round, ["ANANAS"], 500, user=user)
    assert single.status_code == 201, single.text
    assert wallet(client, user) == 3500

    # 4. Tirage et règlement automatique
    sql.execute("update public.game_rounds set status = 'closed' where id = %s", (fruits_round,))
    sql.execute("select private.draw_round(%s)", (fruits_round,))
    mine = {b["id"]: b for b in client.get("/v1/bets", headers=h).json()}
    s, o = mine[sure.json()["id"]], mine[single.json()["id"]]
    assert s["status"] == "won" and s["actual_payout"] > 0, "20 fruits : toujours gagnant"
    assert o["status"] == ("won" if o["round_result"]["fruit"] == "ANANAS" else "lost")
    payouts = s["actual_payout"] + o["actual_payout"]
    assert wallet(client, user) == 3500 + payouts

    v = client.get(f"/v1/rounds/{fruits_round}/verify").json()
    assert v["commitment_ok"] and v["result_ok"], "tirage vérifiable par le joueur"
    summary = client.get("/v1/bets/summary", headers=h).json()
    assert (summary["bet_count"], summary["total_staked"], summary["total_won"]) == (2, 1500, payouts)
    assert summary["net"] == payouts - 1500

    # 5. Retrait de 2 000 F : bloqué aussitôt, alertes levées (peu joué, juste après un dépôt), puis payé
    r = client.post("/v1/withdrawals", headers={**h, "Idempotency-Key": uuid.uuid4().hex},
                    json={"amount": 2000, "method": "mobile_money", "payout_account": phone})
    assert r.status_code == 201, r.text
    wdr = r.json()
    after_hold = 3500 + payouts - 2000
    assert wallet(client, user) == after_hold
    alerts = client.get(f"/v1/admin/risk-events?client_id={me['public_id']}", headers=auth(ADMIN_D)).json()
    assert {"low_turnover", "quick_withdrawal"} <= {a["kind"] for a in alerts}
    for a in alerts:
        assert client.post(f"/v1/admin/risk-events/{a['id']}/resolve", headers=auth(ADMIN_D),
                           json={"note": "Joueur vérifié par téléphone"}).status_code == 200
    for action in ("review", "approve", "pay"):
        r = client.post(f"/v1/admin/withdrawals/{wdr['id']}/{action}", headers=auth(ADMIN_D))
        assert r.status_code == 200, r.text
    assert r.json()["status"] == "paid"
    assert wallet(client, user) == after_hold

    # 6. Question au support, réponse de l'équipe
    t = client.post("/v1/support/tickets", headers=h, json={
        "category": "withdrawal", "subject": "Retrait reçu ?", "message": "Je vérifie mon Mobile Money.",
        "related_reference": wdr["reference"]}).json()
    client.post(f"/v1/admin/support/tickets/{t['id']}/messages", headers=auth(ADMIN_D), json={"body": "Payé à 10 h."})
    assert client.get("/v1/support/tickets", headers=h).json()[0]["unread"] == 1

    # 7. Notifications reçues tout au long du parcours
    kinds = {r[0] for r in sql.execute("select type from public.notifications where user_id = %s", (user,))}
    assert {"deposit_approved", "withdrawal_paid", "support_reply"} <= kinds, kinds

    # 8. L'historique et le ledger racontent la même histoire que le solde
    items = client.get("/v1/wallet/transactions?limit=50", headers=h).json()["items"]
    assert sum(i["amount"] for i in items) == after_hold
    assert items[0]["balance_after"] == after_hold
    ledger = sql.execute(
        "select coalesce(sum(t.amount), 0) from public.wallet_transactions t "
        "join public.wallets w on w.id = t.wallet_id where w.user_id = %s", (user,)).fetchone()[0]
    assert ledger == after_hold
