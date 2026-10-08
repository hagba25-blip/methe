from app.draw import rng, verify

SYMBOLS = ["POMME", "ORANGE", "KIWI"]


def _row(seed, game="FRUITS", tamper=False):
    rid = "11111111-1111-1111-1111-111111111111"
    result = verify.recompute(game, seed, rid, SYMBOLS)
    if tamper:
        result = {"fruit": next(s for s in SYMBOLS if s != result["fruit"])}
    return {"id": rid, "game_code": game, "revealed_seed": seed, "commitment_hash": rng.commitment(seed),
            "result": result}


def test_verify_ok():
    v = verify.verify(_row(rng.new_seed()), SYMBOLS)
    assert v["commitment_ok"] and v["result_ok"]


def test_verify_detects_tampered_result():
    v = verify.verify(_row(rng.new_seed(), tamper=True), SYMBOLS)
    assert v["commitment_ok"] and not v["result_ok"] and "ÉCHEC" in v["explanation"]


def test_verify_detects_swapped_seed():
    row = _row(rng.new_seed(), game="LONATO")
    row["commitment_hash"] = rng.commitment(rng.new_seed())
    assert not verify.verify(row, SYMBOLS)["commitment_ok"]
