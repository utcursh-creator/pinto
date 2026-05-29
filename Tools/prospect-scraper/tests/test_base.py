# tests/test_base.py
import sqlite3
from prospect_scraper import db
from prospect_scraper.sourcing import base
from prospect_scraper.models import JobPost, Source


def _job(company="Acme", role="Automation Engineer"):
    return JobPost(source=Source.weworkremotely, source_url="u", company=company,
                   role=role, description="d")


def test_insert_jobs_counts_only_new():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    db.init_db(conn)
    n1 = base.insert_jobs(conn, [_job("A"), _job("B")])
    n2 = base.insert_jobs(conn, [_job("A"), _job("C")])  # A dup, C new
    assert n1 == 2
    assert n2 == 1
    conn.close()
