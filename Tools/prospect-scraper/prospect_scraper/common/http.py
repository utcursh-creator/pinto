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

    def get_text(self, url: str) -> str:
        resp = self._client.get(url)
        resp.raise_for_status()
        if self.delay:
            time.sleep(self.delay)
        return resp.text

    def close(self) -> None:
        self._client.close()
