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
