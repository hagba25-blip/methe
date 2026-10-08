"""Phase 9 : tableau de bord administrateur et journal des actions."""

import os
import uuid

import pytest

from tests.test_api import USER_A
from tests.test_phase2 import USER_B, auth, sql  # noqa: F401  (fixture)
from tests.test_phase3 import ADMIN_D as ADMIN
from tests.test_phase5 import USER_E
from tests.test_phase6 import bet, client, fruits_round  # noqa: F401  (fixtures)

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


def dash(client, user=ADMIN, **params):
    return client.get("/v1/admin/dashboard", headers=auth(user), params=params)


def test_dashboard_requires_staff(client):
    assert dash(client, USER_A).status_code == 403
    assert client.get("/v1/admin/dashboard").status_code in (401, 403)


def test_dashboard_tracks_bets_and_settlement(client, sql, fruits_round):
    start = dash(client, period="today").json()
    assert start["viewer_role"] == "finance" and start["currency_code"] == "XOF"
    assert len(start["daily"]) == 1 and {w["code"] for w in start["system_wallets"]} >= {"HOUSE", "TREASURY"}
    assert [g["game_code"] for g in start["games"]] == ["FRUITS", "LONATO"]

    bet(client, fruits_round, ["POMME"], 300, key=uuid.uuid4().hex)
    mid = dash(client, period="today").json()
    assert mid["bets"]["bet_count"] == start["bets"]["bet_count"] + 1
    assert mid["bets"]["staked"] == start["bets"]["staked"] + 300
    assert mid["bets"]["pending_stake"] == start["bets"]["pending_stake"] + 300
    assert mid["daily"][-1]["staked"] == start["daily"][-1]["staked"] + 300
    fruits = next(g for g in mid["games"] if g["game_code"] == "FRUITS")
    assert fruits["staked"] >= 300
    assert any(r["id"] == fruits_round and r["staked"] == 300 for r in mid["recent_rounds"])

    sql.execute("update public.game_rounds set status = 'closed' where id = %s", (fruits_round,))
    sql.execute("select private.draw_round(%s)", (fruits_round,))
    end = dash(client, period="today").json()
    paid = end["bets"]["paid"] - start["bets"]["paid"]
    assert paid in (0, 270), "seul pari de la cagnotte : 300 − 10 % ou perdu"
    assert end["bets"]["gross_revenue"] == start["bets"]["gross_revenue"] + 300 - paid
    assert sum(g["gross_revenue"] for g in end["games"]) == end["bets"]["gross_revenue"]


def test_dashboard_periods(client):
    week = dash(client).json()
    assert len(week["daily"]) == 7
    assert len(dash(client, period="30d").json()["daily"]) == 30
    assert dash(client, period="year").status_code == 422


def test_admin_actions_log(client, sql):
    sql.execute("select private.grant_staff_role('yao@example.com', 'admin')")
    assert client.get("/v1/admin/actions", headers=auth(ADMIN)).status_code == 403, "réservé admin"
    pid = sql.execute("select public_id from public.profiles where id = %s", (USER_A,)).fetchone()[0]
    client.get(f"/v1/admin/users/{pid}", headers=auth(USER_E))
    actions = client.get("/v1/admin/actions", headers=auth(USER_E), params={"limit": 5}).json()
    assert actions[0]["action"] == "view_user" and actions[0]["target_id"] == pid
    older = client.get("/v1/admin/actions", headers=auth(USER_E), params={"before": actions[0]["id"]}).json()
    assert all(a["id"] < actions[0]["id"] for a in older)
    assert client.get("/v1/admin/actions", headers=auth(USER_B)).status_code == 403
