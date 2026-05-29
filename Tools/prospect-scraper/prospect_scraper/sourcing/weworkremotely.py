# prospect_scraper/sourcing/weworkremotely.py
#
# Selectors discovered from a live fetch on 2026-05-29 against
# https://weworkremotely.com/categories/remote-programming-jobs
#
# Important: WWR content-negotiates on the Accept header. With the project's
# default client (no explicit Accept) the URL returns an RSS/XML feed; with a
# browser-like "Accept: text/html" it returns the server-rendered HTML parsed
# here. The fetch step (Task 4) must send that header.
#
# The listing page renders a flat list of <li> entries. Two kinds appear:
#   - Real jobs:  <li class="new-listing-container"> containing a job link
#                 <a class="listing-link--unlocked" href="/remote-jobs/...">.
#   - Sponsored ads: <li class="... listing-ad ..."> which share the
#                 new-listing-container class but have NO title and NO job
#                 link. They are skipped because title_node is None.
#
# Selector map (relative to each job <li>):
#   job entry: li.new-listing-container
#   title:     span.new-listing__header__title__text
#   company:   p.new-listing__company-name        (trailing <img> icon; text(strip=True) drops it)
#   link:      a.listing-link--unlocked  -> href is relative "/remote-jobs/..."
#   region:    p.new-listing__company-headquarters (mapped to location, best effort)
import sqlite3

from selectolax.parser import HTMLParser

from prospect_scraper.common.http import HttpClient
from prospect_scraper.models import JobPost, Source
from prospect_scraper.sourcing import base
from prospect_scraper.sourcing.remoteok import matches_keywords

WWR_BASE = "https://weworkremotely.com"
WWR_CATEGORY_URL = "https://weworkremotely.com/categories/remote-programming-jobs"

JOB_ENTRY_SELECTOR = "li.new-listing-container"
TITLE_SELECTOR = "span.new-listing__header__title__text"
COMPANY_SELECTOR = "p.new-listing__company-name"
LINK_SELECTOR = "a.listing-link--unlocked"
REGION_SELECTOR = "p.new-listing__company-headquarters"


def parse_jobs(html: str, keywords: list[str]) -> list[JobPost]:
    tree = HTMLParser(html)
    jobs: list[JobPost] = []
    for node in tree.css(JOB_ENTRY_SELECTOR):
        title_node = node.css_first(TITLE_SELECTOR)
        if title_node is None:
            # Sponsored ad or any non-job entry: no title, skip it.
            continue
        role = title_node.text(strip=True)
        if not role:
            continue

        company_node = node.css_first(COMPANY_SELECTOR)
        company = company_node.text(strip=True) if company_node else ""
        company = company or "Unknown"

        link_node = node.css_first(LINK_SELECTOR)
        href = link_node.attributes.get("href", "") if link_node else ""
        href = href or ""
        url = href if href.startswith("http") else f"{WWR_BASE}{href}"

        region_node = node.css_first(REGION_SELECTOR)
        location = region_node.text(strip=True) if region_node else None
        location = location or None

        haystack = f"{role} {company}"
        if not matches_keywords(haystack, keywords):
            continue

        jobs.append(JobPost(
            source=Source.weworkremotely,
            source_url=url,
            company=company,
            role=role,
            description="",  # WWR list view has no description; enrich later.
            location=location,
        ))
    return jobs


def fetch(client: HttpClient) -> str:
    # WWR content-negotiates: request HTML or it returns an RSS feed.
    return client.get_text(WWR_CATEGORY_URL, headers={"Accept": "text/html"})


def run(conn: sqlite3.Connection, client: HttpClient, keywords: list[str]) -> int:
    html = fetch(client)
    jobs = parse_jobs(html, keywords)
    return base.insert_jobs(conn, jobs)
