from pathlib import Path

from prospect_scraper.sourcing import weworkremotely
from prospect_scraper.models import Source

FIXTURE = Path(__file__).parent / "fixtures" / "weworkremotely_sample.html"

# Keywords that appear in the fixture's programming job titles.
PROGRAMMING_KW = ["engineer", "developer", "automation"]


def _html():
    return FIXTURE.read_text()


def test_parse_returns_jobposts_with_source_set():
    jobs = weworkremotely.parse_jobs(_html(), keywords=PROGRAMMING_KW)
    assert jobs, "expected at least one job from the fixture"
    assert all(j.source == Source.weworkremotely for j in jobs)
    assert all(j.role for j in jobs)
    assert all(j.source_url.startswith("http") for j in jobs)


def test_parse_extracts_expected_roles():
    jobs = weworkremotely.parse_jobs(_html(), keywords=PROGRAMMING_KW)
    roles = [j.role for j in jobs]
    assert "Senior Software Engineer II" in roles
    assert "Senior Fullstack Engineer (Ruby+React)" in roles
    assert "Humbly Confident Senior iOS Engineer" in roles
    # The non-programming job must be filtered out by the programming keywords.
    assert "Marketing Coordinator" not in roles


def test_parse_maps_company_and_absolute_url():
    jobs = weworkremotely.parse_jobs(_html(), keywords=["software engineer"])
    j = next(x for x in jobs if x.role == "Senior Software Engineer II")
    assert j.company == "Nomad"
    assert j.source_url == "https://weworkremotely.com/remote-jobs/nomad-senior-software-engineer-ii"


def test_parse_skips_ad_listing_without_title():
    # The ClickUp sponsored ad has a company name but no job title/link;
    # a broad keyword that would match its text must still not yield it.
    jobs = weworkremotely.parse_jobs(_html(), keywords=PROGRAMMING_KW)
    companies = [j.company for j in jobs]
    assert "ClickUp" not in companies


def test_parse_keyword_filter_excludes_nonmatching():
    # Use a keyword that matches NOTHING in the fixture.
    jobs = weworkremotely.parse_jobs(_html(), keywords=["zzzznomatch"])
    assert jobs == []
