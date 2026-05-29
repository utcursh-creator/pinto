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
