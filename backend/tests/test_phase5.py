"""Phase 5 : moteur de tirage, résultats publiés et vérification indépendante.

La base locale contient les tours simulés par supabase/tests/test_draws.sql.
"""

import os
import secrets
import uuid

import pytest
from fastapi.testclient import TestClient

from app.draw import rng
from main import create_app
from tests.test_phase2 import USER_B, auth, sql  # noqa: F401  (fixture)

USER_E = "00000000-0000-0000-0000-00000000000e"

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")


@pytest.fixture
def client():
    with TestClient(create_app()) as c:
        yield c


def test_sql_and_python_draws_agree(sql):
    """Le tirage fait dans la base et l'implémentation Python de rng.py donnent
    exactement le même résultat pour la même graine : la vérification est réelle."""
    symbols = [r[0] for r in sql.execute("select code from public.game_symbols where game_code = 'FRUITS'")]
    for _ in range(200):
        seed, rid = secrets.token_hex(32), str(uuid.uuid4())
        fruit, lonato = sql.execute(
            "select private.compute_result('FRUITS', %s, %s), private.compute_result('LONATO', %s, %s)",
            (seed, rid, seed, rid)).fetchone()
        assert fruit == {"fruit": rng.draw_fruit(seed, rid, symbols)}
        assert lonato == {"numbers": rng.draw_lonato(seed, rid)}


def test_results_are_published_and_verifiable(client):
    for game in ("FRUITS", "LONATO"):
        results = client.get(f"/v1/rounds/results?game={game}").json()
        assert results, game
        last = results[0]
        assert last["status"] == "published" and last["revealed_seed"] and last["result"]
        v = client.get(f"/v1/rounds/{last['id']}/verify").json()
        assert v["commitment_ok"] and v["result_ok"], v
        assert v["recomputed"] == last["result"]


def test_open_round_hides_seed(client):
    rounds = client.get("/v1/rounds/upcoming?game=FRUITS").json()
    current = next(r for r in rounds if r["status"] == "open")
    assert current["commitment_hash"] and current["revealed_seed"] is None and current["result"] is None
    v = client.get(f"/v1/rounds/{current['id']}/verify").json()
    assert v["commitment_ok"] is False and "pas encore publié" in v["explanation"]
    assert client.get("/v1/rounds/upcoming?game=AUTRE").status_code == 422
    assert client.get(f"/v1/rounds/{uuid.uuid4()}").status_code == 404


def test_results_pagination(client):
    page1 = client.get("/v1/rounds/results?game=FRUITS&limit=1").json()
    page2 = client.get("/v1/rounds/results", params={"game": "FRUITS", "limit": 1,
                                                     "before": page1[0]["draw_at"]}).json()
    assert page2 and page2[0]["draw_at"] < page1[0]["draw_at"]


def test_admin_engine_controls(client, sql):
    sql.execute("select private.grant_staff_role('yao@example.com', 'admin')")
    assert client.post("/v1/admin/engine/tick", headers=auth(USER_B)).status_code == 403
    r = client.post("/v1/admin/engine/tick", headers=auth(USER_E))
    assert r.status_code == 200 and "created" in r.json()

    target = next(x for x in client.get("/v1/rounds/upcoming?game=LONATO").json() if x["status"] == "scheduled")
    url = f"/v1/admin/rounds/{target['id']}/cancel"
    assert client.post(url, headers=auth(USER_E), json={"reason": ""}).status_code == 422
    assert client.post(url, headers=auth(USER_E), json={"reason": "Maintenance"}).json()["status"] == "cancelled"

    published = client.get("/v1/rounds/results?game=LONATO").json()[0]
    r = client.post(f"/v1/admin/rounds/{published['id']}/cancel", headers=auth(USER_E), json={"reason": "Essai"})
    assert r.status_code == 409
