# tests/test_models.py
from datetime import date
from prospect_scraper.models import JobPost, Source


def test_dedup_key_is_stable_and_normalized():
    a = JobPost(source=Source.remoteok, source_url="u1", company="Acme  ",
                role="Automation Engineer", description="d")
    b = JobPost(source=Source.remoteok, source_url="u2", company="acme",
                role="automation engineer", description="other")
    assert a.dedup_key == b.dedup_key  # case + whitespace normalized


def test_dedup_key_differs_on_different_company_role():
    a = JobPost(source=Source.remoteok, source_url="u", company="Acme",
                role="Automation Engineer", description="d")
    b = JobPost(source=Source.remoteok, source_url="u", company="Beta",
                role="Automation Engineer", description="d")
    assert a.dedup_key != b.dedup_key


def test_post_date_optional():
    j = JobPost(source=Source.remoteok, source_url="u", company="Acme",
                role="r", description="d", post_date=date(2026, 5, 1))
    assert j.post_date == date(2026, 5, 1)
