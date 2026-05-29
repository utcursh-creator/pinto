import json
from pathlib import Path

from prospect_scraper.sourcing import remoteok
from prospect_scraper.models import Source

FIXTURE = Path(__file__).parent / "fixtures" / "remoteok_sample.json"


def _raw():
    return json.loads(FIXTURE.read_text())


def test_parse_skips_legend_element():
    jobs = remoteok.parse_jobs(_raw(), keywords=["automation"])
    assert all(j.role for j in jobs)  # none are the legend


def test_parse_keyword_filter_keeps_only_matches():
    jobs = remoteok.parse_jobs(_raw(), keywords=["automation"])
    roles = [j.role for j in jobs]
    assert "Process Automation Engineer" in roles
    assert "Frontend Designer" not in roles


def test_parsed_job_fields_mapped():
    jobs = remoteok.parse_jobs(_raw(), keywords=["automation"])
    j = jobs[0]
    assert j.source == Source.remoteok
    assert j.company == "AutoFlow Agency"
    assert j.source_url == "https://remoteok.com/jobs/1"


def test_matches_keywords_uses_word_boundaries_not_substring():
    # "CTO" must match the standalone token, not substrings of other words
    assert remoteok.matches_keywords("CTO wanted", ["CTO"]) is True
    assert remoteok.matches_keywords("factory worker", ["CTO"]) is False
    assert remoteok.matches_keywords("sales director", ["CTO"]) is False
    # multi-word phrases still match
    assert remoteok.matches_keywords("we do process automations daily", ["process automations"]) is True


import sqlite3
from prospect_scraper import db
from prospect_scraper.common.http import HttpClient


class _FakeClient(HttpClient):
    def __init__(self, payload):
        self._payload = payload
        self.delay = 0.0

    def get_json(self, url: str):
        return self._payload

    def close(self):
        pass


def test_run_inserts_only_matching_and_dedupes():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    db.init_db(conn)
    client = _FakeClient(_raw())

    inserted_first = remoteok.run(conn, client, keywords=["automation"])
    inserted_second = remoteok.run(conn, client, keywords=["automation"])

    assert inserted_first == 1   # only the automation agency row
    assert inserted_second == 0  # dedup on second run
    rows = conn.execute("SELECT company FROM prospects").fetchall()
    assert [r["company"] for r in rows] == ["AutoFlow Agency"]
    conn.close()
