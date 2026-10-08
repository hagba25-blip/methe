"""Phase 8 : historique des paris (filtres, pages, bilan) et des transactions."""

import os
from datetime import datetime, timedelta, timezone

import pytest

from tests.test_api import USER_A
from tests.test_phase2 import USER_B, auth, sql  # noqa: F401  (fixture)
from tests.test_phase6 import bet, client, fruits_round  # noqa: F401  (fixtures)

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")

FUTURE = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()


def summary(client, **params):
    r = client.get("/v1/bets/summary", headers=auth(USER_A), params=params)
    assert r.status_code == 200, r.text
    return r.json()


def test_summary_counts_pending_and_settled(client, sql, fruits_round):
    before = summary(client)
    placed = bet(client, fruits_round, ["ANANAS"], 200).json()
    after = summary(client)
    assert after["bet_count"] == before["bet_count"] + 1
    assert after["pending_count"] == before["pending_count"] + 1
    assert after["total_staked"] == before["total_staked"] + 200
    assert after["pending_stake"] == before["pending_stake"] + 200
    assert after["net"] == before["net"], "un pari en cours ne change pas le résultat net"
    assert summary(client, game="LONATO")["total_staked"] <= after["total_staked"]
    assert summary(client, since=FUTURE)["bet_count"] == 0

    sql.execute("update public.game_rounds set status = 'closed' where id = %s", (fruits_round,))
    sql.execute("select private.draw_round(%s)", (fruits_round,))
    settled = client.get(f"/v1/bets/{placed['id']}", headers=auth(USER_A)).json()
    final = summary(client)
    assert final["pending_stake"] == before["pending_stake"]
    assert final["total_won"] == before["total_won"] + settled["actual_payout"]
    assert final["net"] == before["net"] - 200 + settled["actual_payout"]
    assert client.get("/v1/bets/summary", headers=auth(USER_B)).json()["bet_count"] == 0, "bilan personnel"


def test_bets_pages_and_period(client, fruits_round):
    ids = [bet(client, fruits_round, [f], 50).json()["id"] for f in ("CITRON", "FRAISE", "KIWI")]
    first = client.get("/v1/bets", headers=auth(USER_A), params={"limit": 2}).json()
    assert [b["id"] for b in first] == ids[:0:-1]
    rest = client.get("/v1/bets", headers=auth(USER_A), params={"limit": 2, "before": first[-1]["placed_at"]}).json()
    assert rest[0]["id"] == ids[0], "page suivante"
    assert client.get("/v1/bets", headers=auth(USER_A), params={"since": FUTURE}).json() == []


def test_transactions_period_and_description(client, fruits_round):
    bet(client, fruits_round, ["MANGUE"], 50)
    page = client.get("/v1/wallet/transactions", headers=auth(USER_A), params={"kind": "bets", "limit": 1}).json()
    tx = page["items"][0]
    assert tx["tx_type"] == "bet_stake" and tx["label"] == "Mise" and tx["description"]
    assert client.get("/v1/wallet/transactions", headers=auth(USER_A),
                      params={"since": FUTURE}).json() == {"items": [], "next_cursor": None}
