"""Vérification indépendante d'un tirage publié, avec l'implémentation Python
de l'algorithme (rng.py) — distincte de celle qui a tiré dans la base."""

from collections.abc import Sequence

from app.draw import rng


def recompute(game_code: str, seed: str, round_id: str, fruit_symbols: Sequence[str]) -> dict:
    if game_code == "FRUITS":
        return {"fruit": rng.draw_fruit(seed, round_id, fruit_symbols)}
    if game_code == "LONATO":
        return {"numbers": rng.draw_lonato(seed, round_id)}
    raise ValueError(f"Jeu inconnu : {game_code}")


def verify(round_row: dict, fruit_symbols: Sequence[str]) -> dict:
    seed, commitment = round_row["revealed_seed"], round_row["commitment_hash"]
    if not seed or not commitment:
        return {
            "round_id": round_row["id"], "commitment_ok": False, "result_ok": False, "recomputed": None,
            "explanation": "Le tirage n'est pas encore publié : la graine reste secrète jusqu'au résultat.",
        }
    commitment_ok = rng.verify_commitment(seed, commitment)
    recomputed = recompute(round_row["game_code"], seed, str(round_row["id"]), fruit_symbols)
    result_ok = recomputed == round_row["result"]
    explanation = (
        "Vérifié : l'empreinte publiée avant les mises correspond à la graine révélée, "
        "et cette graine redonne exactement le résultat."
        if commitment_ok and result_ok
        else "ÉCHEC de vérification : contactez le support."
    )
    return {"round_id": round_row["id"], "commitment_ok": commitment_ok, "result_ok": result_ok,
            "recomputed": recomputed, "explanation": explanation}
