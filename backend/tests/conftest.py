import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("SUPABASE_JWT_SECRET", "test-secret-test-secret-test-secret-32b")
os.environ.setdefault("DATABASE_URL", os.environ.get("TEST_DATABASE_URL", ""))
