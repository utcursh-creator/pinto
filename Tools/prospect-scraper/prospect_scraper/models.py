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
