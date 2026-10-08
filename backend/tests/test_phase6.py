"""Phase 6 : catalogue des jeux, prise de paris Fruits, règlement et « Mes paris »."""

import os
import uuid

import pytest
from fastapi.testclient import TestClient

from main import create_app
from tests.test_api import USER_A
from tests.test_phase2 import USER_B, auth, sql  # noqa: F401  (fixture)
from tests.test_phase3 import balance

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


@pytest.fixture
def client():
    with TestClient(create_app()) as c:
        yield c


@pytest.fixture
def fruits_round(sql):
    rid = str(uuid.uuid4())
    number = sql.execute("select coalesce(max(round_number), 0) + 1 from public.game_rounds").fetchone()[0]
    sql.execute(
        "insert into public.game_rounds (id, game_code, round_number, opens_at, closes_at, draw_at) "
        "values (%s, 'FRUITS', %s, now() - interval '5 min', now() + interval '30 min', now() + interval '31 min')",
        (rid, number))
    sql.execute("select private.open_round(%s)", (rid,))
    return rid


def bet(client, round_id, selections, stake=100, key=None, game_type="FRUITS", user=USER_A):
    return client.post("/v1/bets", headers={**auth(user), "Idempotency-Key": key or uuid.uuid4().hex},
                       json={"round_id": round_id, "game_type": game_type, "selections": selections, "stake": stake})


def test_catalog(client):
    games = {g["code"]: g for g in client.get("/v1/games").json()}
    fruits = games["FRUITS"]
    assert len(fruits["symbols"]) == 20 and fruits["symbols"][0]["emoji"]
    t = fruits["types"][0]
    assert t["code"] == "FRUITS" and t["min_stake"] == 50
    assert t["odds"] == {"1": {"1": 50.0}, "20": {"1": 1.0}}, "seules les combinaisons avec une cote publiée"
    assert {x["code"] for x in games["LONATO"]["types"]} == {"PERME", "NAPE", "CHOX"}


def test_place_bet_debits_and_settles(client, sql, fruits_round):
    start = balance(client)
    key = uuid.uuid4().hex
    r = bet(client, fruits_round, ["mangue"], 100, key)
    assert r.status_code == 201, r.text
    b = r.json()
    assert b["selections"] == ["MANGUE"] and b["potential_payout"] == 5000 and b["status"] == "pending"
    assert b["reference"].startswith("BET-") and b["odds_snapshot"] == {"1": 50.0}
    assert balance(client) == start - 100

    assert bet(client, fruits_round, ["MANGUE"], 100, key).json()["id"] == b["id"], "double envoi"
    assert balance(client) == start - 100

    sql.execute("update public.game_rounds set status = 'closed' where id = %s", (fruits_round,))
    sql.execute("select private.draw_round(%s)", (fruits_round,))
    settled = client.get(f"/v1/bets/{b['id']}", headers=auth(USER_A)).json()
    won = settled["round_result"]["fruit"] == "MANGUE"
    assert settled["status"] == ("won" if won else "lost") and settled["round_status"] == "settled"
    assert settled["actual_payout"] == (5000 if won else 0)
    assert settled["matched_values"] == (["MANGUE"] if won else [])
    assert balance(client) == start - 100 + settled["actual_payout"]


def test_bet_errors(client, fruits_round):
    assert bet(client, fruits_round, ["POMME"], 49).status_code == 409
    assert bet(client, fruits_round, ["POMME", "KIWI"]).json()["detail"].startswith("Combinaison non disponible")
    assert bet(client, fruits_round, ["BANANE"], 10**9).json()["detail"] == "Solde insuffisant"
    assert bet(client, fruits_round, ["FRAMBOISE"]).json()["detail"] == "Fruit inconnu"
    assert bet(client, str(uuid.uuid4()), ["POMME"]).status_code == 404
    r = client.post("/v1/bets", headers=auth(USER_A),
                    json={"round_id": fruits_round, "game_type": "FRUITS", "selections": ["POMME"], "stake": 50})
    assert r.status_code == 422, "clé d'idempotence obligatoire"


def test_my_bets_filters_and_privacy(client, fruits_round):
    placed = bet(client, fruits_round, [s["code"] for s in client.get("/v1/games").json()[0]["symbols"]], 50).json()
    assert placed["selection_count"] == 20 and placed["potential_payout"] == 50
    mine = client.get("/v1/bets", headers=auth(USER_A)).json()
    assert mine[0]["id"] == placed["id"]
    pending = client.get("/v1/bets?status=pending&game=FRUITS", headers=auth(USER_A)).json()
    assert all(x["status"] == "pending" for x in pending) and placed["id"] in {x["id"] for x in pending}
    assert client.get("/v1/bets", headers=auth(USER_B)).json() == [], "B ne voit pas les paris de A"
    assert client.get(f"/v1/bets/{placed['id']}", headers=auth(USER_B)).status_code == 404
