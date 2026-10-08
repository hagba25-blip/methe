"""Dernier test lancé : recompte tout l'argent et tous les paris après l'ensemble des tests."""

import os
from pathlib import Path

import psycopg
import pytest

pytestmark = pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL non défini")

CHECKS = Path(__file__).resolve().parents[2] / "supabase" / "tests" / "check_invariants.sql"


def test_ledger_and_games_integrity():
    sql = "\n".join(line for line in CHECKS.read_text().splitlines() if not line.startswith("\\"))
    with psycopg.connect(os.environ["TEST_DATABASE_URL"], autocommit=True) as conn:
        notices = []
        conn.add_notice_handler(lambda d: notices.append(d.message_primary))
        conn.execute(sql)
    assert any(n.startswith("INTÉGRITÉ OK") for n in notices), notices
