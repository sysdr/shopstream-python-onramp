"""All configuration comes from environment variables, so the same image runs anywhere."""
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "")
ALLOW_DEMO_ENDPOINTS = os.environ.get("ALLOW_DEMO_ENDPOINTS") == "1"
# The container runs migrations once before starting the workers; tests and local runs migrate on start-up.
RUN_MIGRATIONS_ON_START = os.environ.get("RUN_MIGRATIONS_ON_START", "1") == "1"
