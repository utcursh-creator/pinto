# prospect_scraper/db.py
import sqlite3
from pathlib import Path

from prospect_scraper.models import JobPost

SCHEMA = """
CREATE TABLE IF NOT EXISTS prospects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    dedup_key TEXT UNIQUE NOT NULL,
    source TEXT NOT NULL,
    source_url TEXT NOT NULL,
    company TEXT NOT NULL,
    role TEXT NOT NULL,
    description TEXT NOT NULL,
    location TEXT,
    post_date TEXT,
    company_site TEXT,
    status TEXT NOT NULL DEFAULT 'sourced',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"""


def connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.commit()


def insert_job(conn: sqlite3.Connection, job: JobPost) -> bool:
    """Insert a job. Returns True if inserted, False if it was a duplicate."""
    try:
        conn.execute(
            """INSERT INTO prospects
               (dedup_key, source, source_url, company, role, description,
                location, post_date, company_site)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                job.dedup_key, job.source.value, job.source_url, job.company,
                job.role, job.description, job.location,
                job.post_date.isoformat() if job.post_date else None,
                job.company_site,
            ),
        )
        conn.commit()
        return True
    except sqlite3.IntegrityError:
        return False
