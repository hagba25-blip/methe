from collections import Counter

from app.draw import rng

FRUITS = [f"F{i:02d}" for i in range(20)]


def test_commitment_roundtrip():
    seed = rng.new_seed()
    assert len(seed) == 64
    assert rng.verify_commitment(seed, rng.commitment(seed))
    assert not rng.verify_commitment(rng.new_seed(), rng.commitment(seed))


def test_draw_is_deterministic_and_reproducible():
    seed = rng.new_seed()
    assert rng.draw_lonato(seed, "r1") == rng.draw_lonato(seed, "r1")
    assert rng.draw_fruit(seed, "r1", FRUITS) == rng.draw_fruit(seed, "r1", list(reversed(FRUITS)))


def test_lonato_draw_shape():
    for i in range(500):
        numbers = rng.draw_lonato(rng.new_seed(), f"round-{i}")
        assert len(numbers) == 5 == len(set(numbers))
        assert all(1 <= n <= 90 for n in numbers)
        assert numbers == sorted(numbers)


def test_fruit_distribution_is_roughly_uniform():
    seed = rng.new_seed()
    counts = Counter(rng.draw_fruit(seed, f"r{i}", FRUITS) for i in range(20000))
    assert set(counts) == set(FRUITS)
    assert all(800 < c < 1200 for c in counts.values())  # attendu ≈ 1000
