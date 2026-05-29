import re
import sqlite3

from prospect_scraper.common.http import HttpClient
from prospect_scraper.models import JobPost, Source
from prospect_scraper.sourcing import base

REMOTEOK_API = "https://remoteok.com/api"


def matches_keywords(text: str, keywords: list[str]) -> bool:
    # Word-boundary match so short tokens like "CTO" do not match inside
    # unrelated words (e.g. "factory", "director"). Phrases match verbatim.
    for k in keywords:
        if re.search(rf"\b{re.escape(k)}\b", text, re.IGNORECASE):
            return True
    return False


def parse_jobs(raw: list[dict], keywords: list[str]) -> list[JobPost]:
    jobs: list[JobPost] = []
    for item in raw:
        position = item.get("position")
        if not position:  # legend/metadata element has no position
            continue
        haystack = " ".join([
            position,
            item.get("description", ""),
            " ".join(item.get("tags", []) or []),
        ])
        if not matches_keywords(haystack, keywords):
            continue
        jobs.append(JobPost(
            source=Source.remoteok,
            source_url=item.get("url", ""),
            company=item.get("company") or "Unknown",
            role=position,
            description=item.get("description", ""),
            location=item.get("location") or None,
        ))
    return jobs


def fetch(client: HttpClient) -> list[dict]:
    return client.get_json(REMOTEOK_API)


def run(conn: sqlite3.Connection, client: HttpClient, keywords: list[str]) -> int:
    """Fetch, parse, filter, insert. Returns count of newly inserted rows."""
    raw = fetch(client)
    jobs = parse_jobs(raw, keywords)
    return base.insert_jobs(conn, jobs)
