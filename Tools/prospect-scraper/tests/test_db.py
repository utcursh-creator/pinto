# tests/test_db.py
from prospect_scraper import db
from prospect_scraper.models import JobPost, Source


def _job(company="Acme", role="Automation Engineer"):
    return JobPost(source=Source.remoteok, source_url="u", company=company,
                   role=role, description="d")


def test_insert_returns_true_then_false_on_duplicate(conn):
    assert db.insert_job(conn, _job()) is True
    assert db.insert_job(conn, _job()) is False  # same dedup key


def test_inserted_row_has_sourced_status(conn):
    db.insert_job(conn, _job())
    row = conn.execute("SELECT status FROM prospects").fetchone()
    assert row["status"] == "sourced"


def test_distinct_jobs_both_insert(conn):
    assert db.insert_job(conn, _job(company="Acme")) is True
    assert db.insert_job(conn, _job(company="Beta")) is True
    count = conn.execute("SELECT COUNT(*) AS n FROM prospects").fetchone()["n"]
    assert count == 2
