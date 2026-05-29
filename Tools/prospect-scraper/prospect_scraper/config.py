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
