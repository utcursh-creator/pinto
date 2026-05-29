# tests/test_config.py
from pathlib import Path
from prospect_scraper.config import Settings
from prospect_scraper.constants import DEFAULT_KEYWORDS


def test_settings_defaults(monkeypatch):
    monkeypatch.delenv("DB_PATH", raising=False)
    monkeypatch.delenv("REQUEST_DELAY_SECONDS", raising=False)
    s = Settings(_env_file=None)
    assert s.request_delay_seconds == 2.0
    assert isinstance(s.db_path, Path)


def test_settings_env_override(monkeypatch):
    monkeypatch.setenv("REQUEST_DELAY_SECONDS", "0.0")
    s = Settings(_env_file=None)
    assert s.request_delay_seconds == 0.0


def test_default_keywords_present():
    assert "process automations" in DEFAULT_KEYWORDS
    assert "Forward Deployed Engineer" in DEFAULT_KEYWORDS
