# -*- coding: utf-8 -*-
"""
database.py -- Fetal death in MIMIC-IV (model M3)

Connection helpers for the local PostgreSQL instance that holds the MIMIC-IV schema.
All parameters come from environment variables (see .env.example), so no credential
is ever committed.
"""
import os
import sqlalchemy as alchemy

from pathlib import Path

# Load the variables of the .env file at the project root (one level above libraries/),
# whatever the folder the notebook or script runs from.
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"
try:
    from dotenv import load_dotenv
    load_dotenv(ENV_FILE, override=True)
except ImportError:
    if ENV_FILE.exists():
        raise ImportError(
            "python-dotenv is not installed, so the .env file cannot be read. "
            "Install it in the notebook kernel with: %pip install python-dotenv"
        )


def get_connect_database():
    """Return a SQLAlchemy engine for the local MIMIC-IV PostgreSQL database.

    MIMICIV_DB_PASSWORD has no default on purpose: the function raises if it is
    missing, rather than connecting with a blank password.
    """
    driver = "postgresql+psycopg2"
    user = os.environ.get("MIMICIV_DB_USER", "postgres")
    password = os.environ.get("MIMICIV_DB_PASSWORD")
    host = os.environ.get("MIMICIV_DB_HOST", "localhost")
    port = os.environ.get("MIMICIV_DB_PORT", "5433")
    database = os.environ.get("MIMICIV_DB_NAME", "mimiciv")

    if not password:
        raise RuntimeError(
            f"MIMICIV_DB_PASSWORD is not set. Expected file: {ENV_FILE}. Copy .env.example "
            "to .env at the project root and fill in your own local Postgres password."
        )

    return alchemy.create_engine(f"{driver}://{user}:{password}@{host}:{port}/{database}")


def disconnect_database(engine):
    engine.dispose()
