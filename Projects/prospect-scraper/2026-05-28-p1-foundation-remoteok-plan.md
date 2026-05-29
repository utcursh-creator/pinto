# Prospect Engine - Plan 1: Foundation + RemoteOK Sourcing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Python project skeleton and the first source (RemoteOK), so a CLI run fetches matching job posts and writes deduplicated rows into sqlite.

**Architecture:** Modular Python package under `Tools/prospect-scraper/`. sqlite is the source of truth for state. A source module fetches + parses + keyword-filters posts into `JobPost` models, which are inserted into sqlite with dedup. CLI orchestrates. External HTTP is mocked in tests (respx); no live keys needed for Plan 1.

**Tech Stack:** Python 3.12 (via uv), pydantic v2, pydantic-settings, httpx, typer, pytest, respx.

**Phase roadmap (for context, only Plan 1 is detailed here):**
- **P1 (this plan): Foundation + RemoteOK sourcing**
- P2: remaining self-built sources (WeWorkRemotely, Workable, n8n jobs) + HTML parsing (selectolax)
- P3: Apify sources (Indeed, LinkedIn) behind the source interface
- P4: Probing (cheap rule-based cull)
- P5: Qualification (OpenRouter classifier)
- P6: Enrichment (email waterfall + company data)
- P7: Nurturing (copy gen + sequencer + Mailtrap)
- P8: Output (vault markdown + TaskNotes view) + CLI full-run orchestration

---

## File Structure (Plan 1)

```
Tools/prospect-scraper/
  pyproject.toml                      # uv project + deps
  .gitignore                          # ignore .env, *.db, __pycache__
  .env.example                        # documented env vars
  prospect_scraper/
    __init__.py
    constants.py                      # DEFAULT_KEYWORDS
    config.py                         # Settings (pydantic-settings)
    models.py                         # Source enum, JobPost
    db.py                             # sqlite schema, connect, init_db, insert_job
    common/
      __init__.py
      http.py                         # HttpClient (httpx + politeness delay)
    sourcing/
      __init__.py
      remoteok.py                     # fetch + parse + run
    cli.py                            # typer app: `source --board remoteok`
  tests/
    __init__.py
    conftest.py                       # fixtures: tmp db conn, sample loader
    fixtures/
      remoteok_sample.json            # captured RemoteOK API shape
    test_models.py
    test_db.py
    test_config.py
    test_http.py
    test_remoteok.py
    test_cli.py
```

Responsibilities: `models.py` defines data shapes + dedup; `db.py` owns persistence; `sourcing/remoteok.py` owns one source; `common/http.py` owns network politeness; `cli.py` wires them. Each file has one job.

---

## Task 1: Project scaffold

**Files:**
- Create: `Tools/prospect-scraper/pyproject.toml`
- Create: `Tools/prospect-scraper/.gitignore`
- Create: `Tools/prospect-scraper/.env.example`
- Create: `Tools/prospect-scraper/prospect_scraper/__init__.py` (empty)
- Create: `Tools/prospect-scraper/tests/__init__.py` (empty)

- [ ] **Step 1: Create `pyproject.toml`**

```toml
[project]
name = "prospect-scraper"
version = "0.1.0"
description = "Outbound prospect engine"
requires-python = ">=3.12"
dependencies = [
    "httpx>=0.27",
    "pydantic>=2.7",
    "pydantic-settings>=2.3",
    "typer>=0.12",
]

[dependency-groups]
dev = [
    "pytest>=8.2",
    "respx>=0.21",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["prospect_scraper"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-q"
```

- [ ] **Step 2: Create `.gitignore`**

```gitignore
__pycache__/
*.py[cod]
.venv/
.env
*.db
.pytest_cache/
```

- [ ] **Step 3: Create `.env.example`**

```dotenv
# Used in later phases; safe to leave blank for Plan 1
OPENROUTER_API_KEY=
APIFY_API_TOKEN=
APOLLO_API_KEY=
HUNTER_API_KEY=
VERIFIER_API_KEY=
MAILTRAP_HOST=
MAILTRAP_PORT=
MAILTRAP_USER=
MAILTRAP_PASS=
# Settings overrides (optional)
DB_PATH=prospect_scraper.db
REQUEST_DELAY_SECONDS=2.0
```

- [ ] **Step 4: Create empty `prospect_scraper/__init__.py` and `tests/__init__.py`**

- [ ] **Step 5: Provision env and verify**

Run: `cd Tools/prospect-scraper && uv sync`
Expected: creates `.venv` with Python 3.12 (uv auto-provisions), installs deps, no errors.
Run: `uv run python -c "import httpx, pydantic, typer; print('ok')"`
Expected: prints `ok`

- [ ] **Step 6: Commit**

```bash
git add Tools/prospect-scraper/pyproject.toml Tools/prospect-scraper/.gitignore Tools/prospect-scraper/.env.example Tools/prospect-scraper/prospect_scraper/__init__.py Tools/prospect-scraper/tests/__init__.py
git commit -m "chore: scaffold prospect-scraper project"
```

---

## Task 2: Models (Source enum, JobPost, dedup key)

**Files:**
- Create: `Tools/prospect-scraper/prospect_scraper/models.py`
- Test: `Tools/prospect-scraper/tests/test_models.py`

- [ ] **Step 1: Write the failing test**

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Tools/prospect-scraper && uv run pytest tests/test_models.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'prospect_scraper.models'`

- [ ] **Step 3: Write minimal implementation**

```python
# prospect_scraper/models.py
import hashlib
from datetime import date
from enum import Enum

from pydantic import BaseModel


class Source(str, Enum):
    remoteok = "remoteok"
    weworkremotely = "weworkremotely"
    workable = "workable"
    n8n_community = "n8n_community"
    indeed = "indeed"
    linkedin = "linkedin"


class JobPost(BaseModel):
    source: Source
    source_url: str
    company: str
    role: str
    description: str
    location: str | None = None
    post_date: date | None = None
    company_site: str | None = None

    @property
    def dedup_key(self) -> str:
        norm = f"{self.company.strip().lower()}|{self.role.strip().lower()}"
        return hashlib.sha256(norm.encode()).hexdigest()[:16]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_models.py -v`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add prospect_scraper/models.py tests/test_models.py
git commit -m "feat: JobPost model with normalized dedup key"
```

---

## Task 3: sqlite persistence (schema, connect, init, insert with dedup)

**Files:**
- Create: `Tools/prospect-scraper/prospect_scraper/db.py`
- Test: `Tools/prospect-scraper/tests/test_db.py`
- Create: `Tools/prospect-scraper/tests/conftest.py`

- [ ] **Step 1: Write conftest fixture + failing test**

```python
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
```

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_db.py -v`
Expected: FAIL with `ModuleNotFoundError` or `AttributeError: module 'prospect_scraper.db' has no attribute 'init_db'`

- [ ] **Step 3: Write minimal implementation**

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_db.py -v`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add prospect_scraper/db.py tests/test_db.py tests/conftest.py
git commit -m "feat: sqlite persistence with dedup-on-insert"
```

---

## Task 4: Config + constants

**Files:**
- Create: `Tools/prospect-scraper/prospect_scraper/config.py`
- Create: `Tools/prospect-scraper/prospect_scraper/constants.py`
- Test: `Tools/prospect-scraper/tests/test_config.py`

- [ ] **Step 1: Write the failing test**

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_config.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'prospect_scraper.config'`

- [ ] **Step 3: Write minimal implementation**

```python
# prospect_scraper/constants.py
DEFAULT_KEYWORDS: list[str] = [
    "AI automation partner",
    "Automation Partner",
    "Process Automation Engineer",
    "Automation Engineer",
    "Forward Deployed Engineer",
    "CTO",
    "process automations",
    "custom automation development",
]
```

```python
# prospect_scraper/config.py
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    db_path: Path = Path("prospect_scraper.db")
    request_delay_seconds: float = 2.0

    openrouter_api_key: str = ""
    apify_api_token: str = ""
    apollo_api_key: str = ""
    hunter_api_key: str = ""


def get_settings() -> Settings:
    return Settings()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_config.py -v`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add prospect_scraper/config.py prospect_scraper/constants.py tests/test_config.py
git commit -m "feat: settings + default keyword set"
```

---

## Task 5: HTTP client (politeness delay, JSON)

**Files:**
- Create: `Tools/prospect-scraper/prospect_scraper/common/__init__.py` (empty)
- Create: `Tools/prospect-scraper/prospect_scraper/common/http.py`
- Test: `Tools/prospect-scraper/tests/test_http.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_http.py
import httpx
import pytest
import respx
from prospect_scraper.common.http import HttpClient


@respx.mock
def test_get_json_returns_parsed_body():
    respx.get("https://example.com/api").mock(
        return_value=httpx.Response(200, json=[{"a": 1}])
    )
    client = HttpClient(delay_seconds=0.0)
    data = client.get_json("https://example.com/api")
    client.close()
    assert data == [{"a": 1}]


@respx.mock
def test_get_json_raises_on_error_status():
    respx.get("https://example.com/api").mock(return_value=httpx.Response(500))
    client = HttpClient(delay_seconds=0.0)
    with pytest.raises(httpx.HTTPStatusError):
        client.get_json("https://example.com/api")
    client.close()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_http.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'prospect_scraper.common.http'`

- [ ] **Step 3: Write minimal implementation**

```python
# prospect_scraper/common/http.py
import time

import httpx


class HttpClient:
    def __init__(self, delay_seconds: float = 2.0):
        self.delay = delay_seconds
        self._client = httpx.Client(
            timeout=30,
            headers={"User-Agent": "Mozilla/5.0 (prospect-scraper research bot)"},
            follow_redirects=True,
        )

    def get_json(self, url: str):
        resp = self._client.get(url)
        resp.raise_for_status()
        if self.delay:
            time.sleep(self.delay)
        return resp.json()

    def close(self) -> None:
        self._client.close()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_http.py -v`
Expected: 2 passed

- [ ] **Step 5: Commit**

```bash
git add prospect_scraper/common/__init__.py prospect_scraper/common/http.py tests/test_http.py
git commit -m "feat: http client with politeness delay"
```

---

## Task 6: RemoteOK parser (keyword filter)

**Files:**
- Create: `Tools/prospect-scraper/prospect_scraper/sourcing/__init__.py` (empty)
- Create: `Tools/prospect-scraper/prospect_scraper/sourcing/remoteok.py`
- Create: `Tools/prospect-scraper/tests/fixtures/remoteok_sample.json`
- Test: `Tools/prospect-scraper/tests/test_remoteok.py`

- [ ] **Step 1: Create the fixture**

The RemoteOK API returns a JSON array whose FIRST element is a legend/metadata object (no `position`), followed by job objects.

```json
[
  {"legal": "RemoteOK legend, not a job"},
  {"id": "1", "company": "AutoFlow Agency", "position": "Process Automation Engineer",
   "description": "We build n8n automations for our clients and need help with delivery.",
   "tags": ["n8n", "automation"], "url": "https://remoteok.com/jobs/1", "location": "Remote EU"},
  {"id": "2", "company": "RandomCorp", "position": "Frontend Designer",
   "description": "Figma and CSS work for our marketing site.",
   "tags": ["design"], "url": "https://remoteok.com/jobs/2", "location": "Remote"}
]
```

- [ ] **Step 2: Write the failing test**

```python
# tests/test_remoteok.py
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `uv run pytest tests/test_remoteok.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'prospect_scraper.sourcing.remoteok'`

- [ ] **Step 4: Write minimal implementation**

```python
# prospect_scraper/sourcing/remoteok.py
from prospect_scraper.models import JobPost, Source

REMOTEOK_API = "https://remoteok.com/api"


def matches_keywords(text: str, keywords: list[str]) -> bool:
    t = text.lower()
    return any(k.lower() in t for k in keywords)


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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `uv run pytest tests/test_remoteok.py -v`
Expected: 3 passed

- [ ] **Step 6: Commit**

```bash
git add prospect_scraper/sourcing/__init__.py prospect_scraper/sourcing/remoteok.py tests/fixtures/remoteok_sample.json tests/test_remoteok.py
git commit -m "feat: RemoteOK parser with keyword filter"
```

---

## Task 7: RemoteOK fetch + run (wire to db)

**Files:**
- Modify: `Tools/prospect-scraper/prospect_scraper/sourcing/remoteok.py` (add `fetch` and `run`)
- Test: `Tools/prospect-scraper/tests/test_remoteok.py` (add run test)

- [ ] **Step 1: Write the failing test (append)**

```python
# tests/test_remoteok.py (append)
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_remoteok.py::test_run_inserts_only_matching_and_dedupes -v`
Expected: FAIL with `AttributeError: module 'prospect_scraper.sourcing.remoteok' has no attribute 'run'`

- [ ] **Step 3: Write minimal implementation (append to remoteok.py)**

```python
# prospect_scraper/sourcing/remoteok.py (append)
import sqlite3

from prospect_scraper import db as db_module
from prospect_scraper.common.http import HttpClient


def fetch(client: HttpClient) -> list[dict]:
    return client.get_json(REMOTEOK_API)


def run(conn: sqlite3.Connection, client: HttpClient, keywords: list[str]) -> int:
    """Fetch, parse, filter, insert. Returns count of newly inserted rows."""
    raw = fetch(client)
    jobs = parse_jobs(raw, keywords)
    inserted = 0
    for job in jobs:
        if db_module.insert_job(conn, job):
            inserted += 1
    return inserted
```

- [ ] **Step 4: Run all tests**

Run: `uv run pytest -v`
Expected: all green (models 3, db 3, config 3, http 2, remoteok 4)

- [ ] **Step 5: Commit**

```bash
git add prospect_scraper/sourcing/remoteok.py tests/test_remoteok.py
git commit -m "feat: RemoteOK fetch+run wired to sqlite with dedup"
```

---

## Task 8: CLI (`source --board remoteok`)

**Files:**
- Create: `Tools/prospect-scraper/prospect_scraper/cli.py`
- Test: `Tools/prospect-scraper/tests/test_cli.py`
- Modify: `Tools/prospect-scraper/pyproject.toml` (add script entry)

- [ ] **Step 1: Write the failing test**

```python
# tests/test_cli.py
import sqlite3
from typer.testing import CliRunner

from prospect_scraper import cli
from prospect_scraper.sourcing import remoteok

runner = CliRunner()


def test_source_remoteok_reports_inserted(monkeypatch, tmp_path):
    db_file = tmp_path / "t.db"

    def fake_run(conn, client, keywords):
        return 5

    monkeypatch.setattr(remoteok, "run", fake_run)
    result = runner.invoke(cli.app, ["source", "--board", "remoteok", "--db", str(db_file)])
    assert result.exit_code == 0
    assert "5" in result.stdout


def test_source_unknown_board_errors():
    result = runner.invoke(cli.app, ["source", "--board", "nope"])
    assert result.exit_code != 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_cli.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'prospect_scraper.cli'`

- [ ] **Step 3: Write minimal implementation**

```python
# prospect_scraper/cli.py
from pathlib import Path

import typer

from prospect_scraper import db as db_module
from prospect_scraper.common.http import HttpClient
from prospect_scraper.config import get_settings
from prospect_scraper.constants import DEFAULT_KEYWORDS
from prospect_scraper.sourcing import remoteok

app = typer.Typer(help="Outbound prospect engine")

# Map board name to its MODULE (not module.run). We resolve `.run` at call
# time so tests that monkeypatch `remoteok.run` take effect.
_BOARDS = {"remoteok": remoteok}


@app.command()
def source(
    board: str = typer.Option(..., "--board", help="Which source to run"),
    db: Path = typer.Option(None, "--db", help="sqlite path (overrides settings)"),
):
    """Run a single source and write rows into sqlite."""
    if board not in _BOARDS:
        typer.echo(f"Unknown board: {board}. Known: {', '.join(_BOARDS)}", err=True)
        raise typer.Exit(code=1)

    settings = get_settings()
    db_path = db or settings.db_path
    conn = db_module.connect(db_path)
    db_module.init_db(conn)
    client = HttpClient(delay_seconds=settings.request_delay_seconds)
    try:
        inserted = _BOARDS[board].run(conn, client, DEFAULT_KEYWORDS)
    finally:
        client.close()
        conn.close()
    typer.echo(f"{board}: inserted {inserted} new prospects")


if __name__ == "__main__":
    app()
```

- [ ] **Step 4: Add script entry to `pyproject.toml`**

Add under `[project]`:

```toml
[project.scripts]
prospect-scraper = "prospect_scraper.cli:app"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `uv run pytest tests/test_cli.py -v`
Expected: 2 passed

- [ ] **Step 6: Full suite + manual smoke**

Run: `uv run pytest -v`
Expected: all green (17 tests total)
Manual smoke (real network, optional): `uv run prospect-scraper source --board remoteok --db /tmp/smoke.db` then `sqlite3 /tmp/smoke.db "SELECT company, role FROM prospects LIMIT 5;"`
Expected: a handful of automation-related rows, or zero if RemoteOK has no current matches (both are valid; the run should not error).

- [ ] **Step 7: Commit**

```bash
git add prospect_scraper/cli.py tests/test_cli.py pyproject.toml
git commit -m "feat: CLI source command for remoteok"
```

---

## Definition of Done (Plan 1)
- `uv run pytest` is fully green (17 tests)
- `uv run prospect-scraper source --board remoteok` runs without error and writes deduped rows to sqlite
- All code committed in small commits
- No live API keys required

## Audit checklist (run skeptically after Plan 1, before Plan 2)
- Does a second run insert 0 (dedup holds across process restarts, not just in-memory)? Verify against a file-backed db, not :memory:.
- Does RemoteOK occasionally rate-limit or return HTML instead of JSON? If so, `get_json` raises; decide whether to catch + log (note for P2 error-handling pass).
- Is the keyword filter too broad ("CTO" matches a lot)? Capture the real hit/junk ratio from the smoke run; feed into P4 probing.
- Are company names ever empty/garbage from RemoteOK? Confirm the "Unknown" fallback does not create dedup collisions.
