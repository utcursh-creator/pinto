# prospect_scraper/cli.py
from pathlib import Path

import typer

from prospect_scraper import db as db_module
from prospect_scraper.common.http import HttpClient
from prospect_scraper.config import get_settings
from prospect_scraper.constants import DEFAULT_KEYWORDS
from prospect_scraper.sourcing import remoteok

app = typer.Typer(help="Outbound prospect engine")


@app.callback()
def main() -> None:
    """Outbound prospect engine."""


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
