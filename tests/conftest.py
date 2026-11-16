"""Tests run against a throwaway database, shopstream_test, created fresh for each test session."""
import os

import psycopg
import pytest

BASE = os.environ.get("DATABASE_URL", "postgresql://shop:shop-local-only@db:5432/shopstream")
TEST_URL = BASE.rsplit("/", 1)[0] + "/shopstream_test"
os.environ["DATABASE_URL"] = TEST_URL


@pytest.fixture(scope="session", autouse=True)
def test_database():
    with psycopg.connect(BASE, autocommit=True) as conn:
        conn.execute("DROP DATABASE IF EXISTS shopstream_test WITH (FORCE)")
        conn.execute("CREATE DATABASE shopstream_test")
    yield TEST_URL


@pytest.fixture(scope="session")
def client(test_database):
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        yield c
