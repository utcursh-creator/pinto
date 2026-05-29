# tests/conftest.py
import sqlite3
import pytest
from prospect_scraper import db


@pytest.fixture
def conn():
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    db.init_db(c)
    yield c
    c.close()
