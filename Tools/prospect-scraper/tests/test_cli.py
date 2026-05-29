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
