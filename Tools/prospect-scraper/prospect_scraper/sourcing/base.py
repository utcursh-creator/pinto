# prospect_scraper/sourcing/base.py
import sqlite3

from prospect_scraper import db as db_module
from prospect_scraper.models import JobPost


def insert_jobs(conn: sqlite3.Connection, jobs: list[JobPost]) -> int:
    """Insert jobs, returning the count of newly inserted (non-duplicate) rows."""
    inserted = 0
    for job in jobs:
        if db_module.insert_job(conn, job):
            inserted += 1
    return inserted
