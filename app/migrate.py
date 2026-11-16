"""Apply migrations/NNN_*.sql in order, once each, recording them in schema_migrations.

Run on start-up (and by hand with: python -m app.migrate). Each file runs in its own transaction,
so a failing migration leaves the database as it was before that file.
"""
import pathlib
import sys

import psycopg

from app.config import DATABASE_URL

MIGRATIONS = pathlib.Path(__file__).resolve().parent.parent / "migrations"


def migrate(url=None):
    applied_now = []
    with psycopg.connect(url or DATABASE_URL, autocommit=True) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())")
        conn.execute("SELECT pg_advisory_lock(4242)")  # two instances starting together must not both migrate
        try:
            done = {r[0] for r in conn.execute("SELECT version FROM schema_migrations")}
            for f in sorted(MIGRATIONS.glob("*.sql")):
                if f.stem in done:
                    continue
                with conn.transaction():
                    conn.execute(f.read_text())
                    conn.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (f.stem,))
                applied_now.append(f.stem)
        finally:
            conn.execute("SELECT pg_advisory_unlock(4242)")
    return applied_now


if __name__ == "__main__":
    print("applied:", migrate() or "nothing new")
    sys.exit(0)
