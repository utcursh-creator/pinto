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
