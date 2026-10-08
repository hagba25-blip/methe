"""Tirage aléatoire sécurisé et vérifiable (protocole commit-reveal).

1. À l'ouverture d'un tirage, le serveur génère une graine secrète de 256 bits
   (module `secrets`, CSPRNG du système) et publie uniquement son empreinte
   SHA-256 (`commitment_hash`), AVANT que le moindre pari soit accepté.
2. À l'heure du tirage, le résultat est dérivé de la graine et de l'identifiant
   du tirage par HMAC-SHA256, avec rejet pour éviter tout biais modulo.
3. À la publication, la graine est révélée : chacun peut vérifier que
   sha256(graine) == commitment_hash et recalculer le résultat.

Le résultat ne dépend d'aucun pari : il est fixé par la graine choisie avant
l'ouverture des mises.
"""

import hashlib
import hmac
import secrets
from collections.abc import Iterator, Sequence

ALGORITHM_VERSION = "hmac-sha256-v1"
LONATO_MIN, LONATO_MAX, LONATO_DRAW_SIZE = 1, 90, 5


def new_seed() -> str:
    return secrets.token_hex(32)


def commitment(seed: str) -> str:
    return hashlib.sha256(bytes.fromhex(seed)).hexdigest()


def verify_commitment(seed: str, commitment_hash: str) -> bool:
    return hmac.compare_digest(commitment(seed), commitment_hash)


def _stream(seed: str, round_id: str) -> Iterator[int]:
    """Suite déterministe d'entiers 32 bits dérivée de (graine, tirage)."""
    key = bytes.fromhex(seed)
    counter = 0
    while True:
        block = hmac.new(key, f"{round_id}:{counter}".encode(), hashlib.sha256).digest()
        for i in range(0, len(block), 4):
            yield int.from_bytes(block[i : i + 4], "big")
        counter += 1


def _uniform(stream: Iterator[int], n: int) -> int:
    """Entier uniforme dans [0, n) sans biais (échantillonnage par rejet)."""
    limit = (2**32 // n) * n
    for value in stream:
        if value < limit:
            return value % n
    raise RuntimeError("unreachable")


def draw_fruit(seed: str, round_id: str, symbols: Sequence[str]) -> str:
    ordered = sorted(symbols)  # ordre canonique, indépendant de l'affichage
    return ordered[_uniform(_stream(seed, round_id), len(ordered))]


def draw_lonato(seed: str, round_id: str) -> list[int]:
    """5 numéros distincts entre 01 et 90 (Fisher-Yates partiel)."""
    pool = list(range(LONATO_MIN, LONATO_MAX + 1))
    stream = _stream(seed, round_id)
    for i in range(LONATO_DRAW_SIZE):
        j = i + _uniform(stream, len(pool) - i)
        pool[i], pool[j] = pool[j], pool[i]
    return sorted(pool[:LONATO_DRAW_SIZE])
