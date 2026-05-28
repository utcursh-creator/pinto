---
type: prd
project: prospect-scraper
date: 2026-05-28
status: approved-pending-review
tags: [prd, outbound, gtm, scraper, prospect-engine]
---

# Outbound Prospect Engine - PRD (v1)

The system Utkarsh follows throughout the build. Outbound is phase 1. The inbound (Twitter content) engine is phase 2 and shares the same core. This doc covers phase 1 only.

## 1. Purpose

Find [[Yosef]]-style partner-prospects (AI/process-automation agencies with delivery overflow) on job boards, qualify them against the ICP, enrich them with contact data, and run a peer-to-peer email sequence. Goal is 2 signed partners at ~$3K/mo each.

This is a tech-leveraged route around the [[GTM-avoidance-pattern]]: the system does sourcing, the human does the conversation.

## 2. Goal and Success Criteria

- **Primary goal**: 2 partners signed (~$3K/mo each, ~$6K/mo new recurring)
- **System success (v1)**: one CLI run produces ~25 qualified, enriched, dedupe-checked prospects as markdown files in the vault, each with a drafted peer-to-peer email, visible in a TaskNotes kanban
- **Process success**: first run produces real data so we can pick apart what worked and optimize. Shipping + learning beats more planning.

## 3. Scope

### In scope (v1, outbound)
- 5-source job-board scraper (sourcing)
- Two-stage filter: cheap probing then LLM qualification
- Email + company enrichment via free tiers
- Per-prospect peer-to-peer email generation (option C positioning)
- 3-touch nurturing sequence (state machine), sandboxed in dev via Mailtrap
- Markdown output to vault, TaskNotes kanban integration
- One-time bulk CLI run, idempotent + resumable

### Out of scope (deferred)
- Inbound Twitter content engine (phase 2, shares the core)
- Newsletter (inbound, phase 2)
- Production email deliverability: real DNS (SPF/DKIM/DMARC), domain warming, paid sender (Smartlead). Deferred until system proves out.
- LinkedIn anything (explicitly excluded, see user platform psychology)
- Upwork scraping (too hostile for v1)
- Scheduling / cron / alerting (v2 upgrade)
- Proxies (abstraction layer present, not wired)

## 4. Positioning Constraint (non-negotiable)

Outbound ships before inbound, so there is no Twitter credibility yet. Every email MUST read peer-to-peer, not vendor-tier:

- NEVER reference the job post ("I saw your post" is banned - it codes the sender as an applicant)
- Lead with a specific observation about their business, not credentials
- Frame as technical fulfillment partner (you sell, I build, your clients use it), not contractor-for-hire
- No em dashes anywhere (standing user rule)
- If a draft reads like a Fiverr pitch, it fails review

The job post is INTEL (who to contact). It is never the narrative.

## 5. Pipeline (5 layers)

```
Sourcing -> Probing -> Qualification -> Enrichment -> Nurturing
 (scrape)   (cheap     (LLM deep-       (email +      (peer email
            rule cull)  score)           company)      sequence)
```

### 5.1 Sourcing
- Sources: RemoteOK (JSON API), WeWorkRemotely, Workable, n8n community jobs, Indeed.de
- Access: RemoteOK via `remoteok.com/api`; others via httpx + selectolax; Playwright only where JS forces it (likely Indeed.de, possibly Workable)
- Keyword set: "AI automation partner", "Automation Partner", "Process Automation Engineer", "Automation Engineer", "Forward Deployed Engineer", "CTO", "process automations", "custom automation development"
- Research task BEFORE coding: audit GitHub for existing scrapers / selector maps per board (Crawlee, Apify, n8n community). Reuse, do not reinvent.
- Politeness delays per board. No proxies in v1 (abstraction layer only).
- Output: raw job-post rows in sqlite (status `sourced`)

### 5.2 Probing (cheap, NO LLM)
Purpose: cull obvious junk before spending LLM + enrichment budget. Rule-based only.
- Agency heuristic (is the poster an agency/studio/consultancy, not an end-user company)
- Recency filter (post within 45 days, configurable)
- ICP pain-signal keyword scan ("backlog", "overwhelmed", "for our clients", "can't deliver", "freelancers", "ongoing", "fulfillment", "our agency")
- Dedup check against sqlite (key: normalized(company + role) + source URL)
- Output: survivors marked `probed_pass`, rest `probed_reject` (kept for audit, not deleted)

### 5.3 Qualification (LLM)
- Model: OpenRouter `claude-haiku-4-5`
- Runs ONLY on `probed_pass` rows (cost control)
- Input: the full post + structured ICP criteria (Section 9)
- Output (structured JSON): `pass` (bool), `score` (0-1), `matched_signals` (list), `reasoning` (2 lines)
- Score bands: `>=0.6` auto-pass to enrichment; `0.4-0.59` -> status `manual_review`; `<0.4` reject
- `manual_review` prospects: still written to the vault as markdown (tag `prospect`, flagged `needs_judgment: true`), but NOT enriched or queued for send until the human promotes them. They surface in the kanban for a yes/no call, so grey-zone leads are not silently lost.
- Volume cap: ~25 auto-pass prospects per run reach enrichment (conserves free tiers, keeps review pile manageable). `manual_review` rows do not count against the cap.

### 5.4 Enrichment (qualified only)
- Email waterfall (stop at first verified hit): website scrape -> Apollo (free 50/mo) -> Hunter (free 25/mo) -> free verifier (NeverBounce / MailboxLayer free tier)
- No email found -> prospect still created, `email_status: not_found`, excluded from send queue
- Also capture: company website, region (US/UK/AU/CA/EU/DE/other), team-size signals, Twitter handle, recent activity
- Output: full prospect record, status `enriched`

### 5.5 Nurturing (email sequence)
- Copy: peer-to-peer insight-led, generated per prospect via OpenRouter, obeying Section 4
- Cadence: 3 touches over 8 days
  - T1: insight / observation about their business
  - T2 (+3 days): different angle + soft value
  - T3 (+5 days): brief last-call
  - Stop on ANY reply
- Sending: provider-abstraction interface. Dev = Mailtrap sandbox (captures, does not deliver). Production sender deferred.
- Reply detection: IMAP poller. Built now, no-op in dev, goes live with DNS later.
- State machine in sqlite: `queued -> t1_sent -> t2_sent -> t3_sent -> done` / `replied` (terminal) / `bounced`

## 6. Architecture

- Language: Python 3.12+, `uv` package manager, pytest (TDD)
- Location: `Tools/prospect-scraper/` (vault subdirectory, shares vault git history)
- Structure:
  ```
  Tools/prospect-scraper/
    pyproject.toml
    .env.example
    prospect_scraper/
      __init__.py
      cli.py              # entrypoint: run + per-stage subcommands
      config.py           # env + settings
      db.py               # sqlite schema + helpers
      models.py           # pydantic models
      sourcing/           # one module per board + base
      probing/            # rule-based filters
      qualification/      # OpenRouter classifier
      enrichment/         # email waterfall + company data
      nurturing/          # copy gen + sequencer + IMAP poller + sender abstraction
      output/             # markdown writer + TaskNotes view generator
      common/             # http client, delays, logging, llm client
    tests/
    docs/                 # copy of this PRD + plan
  ```
- State + dedup: sqlite (source of truth). Vault markdown = human-facing view regenerated from sqlite. On conflict, sqlite wins.
- Output: `Projects/prospect-scraper/prospects/<company-slug>.md` + `TaskNotes/Views/prospects-kanban.base`

## 7. Data Model

### sqlite (source of truth)
`prospects` table (key fields): `id`, `company`, `role`, `source`, `source_url`, `dedup_key`, `post_date`, `post_excerpt`, `status`, `probe_flags` (json), `qual_score`, `qual_signals` (json), `qual_reasoning`, `email`, `email_status`, `region`, `company_site`, `twitter_handle`, `size_signal`, `seq_state`, `t1_sent_at`, `t2_sent_at`, `t3_sent_at`, `replied_at`, `created_at`, `updated_at`

`status` enum: `sourced -> probed_pass | probed_reject -> qualified | manual_review | qual_reject -> enriched -> queued -> done | replied | bounced | error`

### Vault markdown (per prospect, TaskNotes-compatible)
```yaml
---
title: <Company> - <Role>
status: to_review        # to_review|to_send|sent|replied|won|passed
priority: high
scheduled: 2026-05-28
tags: [prospect, <source>, <region>]
company: ...
email: ...
email_status: verified|not_found
source: remoteok|weworkremotely|workable|n8n_community|indeed_de
score: 0.78
region: DE
source_url: ...
twitter_handle: ...
date_scraped: 2026-05-28
---
```
Body: post excerpt, qualification reasoning + matched signals, enrichment data, generated 3 email drafts, status notes.

## 8. Configuration and Secrets
`.env`: `OPENROUTER_API_KEY`, `APOLLO_API_KEY`, `HUNTER_API_KEY`, `VERIFIER_API_KEY`, `MAILTRAP_*`, `IMAP_*` (deferred-live). `.env.example` committed, `.env` gitignored.

## 9. ICP Classifier Criteria (qualification prompt source)

**MUST (filter out if absent)**: poster is agency/studio/consultancy serving clients (not end-user hiring in-house); niche match (n8n / Make / Zapier / process automations / custom automation development / AI integration); strategic role tier (Automation Partner, Process Automation Engineer, Architect, FDE, CTO, Senior Automation Developer), NOT junior/intern/VA/data-entry.

**NICE (boost score)**: team-size signals (1-5 person, boutique, growing studio); revenue anchors ($50-150/hr, $3-15K project, $1-5K/mo retainer); pain signals (backlog, turning down projects, freelancers ghosting, can't deliver, overwhelmed, ongoing fulfillment); geo (US/UK/AU/CA/EU, especially Germany); client-work language; Yosef-stack alignment (n8n, GDPR, EU, multi-client); portfolio hints; tech depth (vector DBs, RAG, custom MCP, AI agents, multi-system).

**DISQUALIFY**: internal IT hire for end-user; junior/intern/entry/VA; crypto/Web3/NFT; pure data-entry / Zapier-tutorial / one-off task; AI hype with no technical scope; LLM-spam template posts.

## 10. Error Handling and Resumability
- Per-stage isolation: one failing post is logged + marked `error`, batch continues
- Resumable: each stage selects rows by input status, so a re-run continues where it stopped
- Idempotent: dedup prevents re-processing seen posts across runs
- API failures (Apollo/Hunter/OpenRouter): retry with backoff, then mark row for that stage and move on

## 11. Testing Strategy (TDD)
- Unit: probing rules, dedup key, score-band routing, email-waterfall fallback order, markdown frontmatter writer, sequencer state transitions
- Integration: each source parser against a saved fixture HTML/JSON (no live calls in tests)
- LLM + external APIs mocked in tests
- Mailtrap used for live-send manual verification, not automated tests

## 12. Decisions Log (locked 2026-05-28)
- Sources: RemoteOK + WeWorkRemotely + Workable + n8n community + Indeed.de (no Upwork)
- Email extraction: hybrid waterfall (scrape -> Apollo -> Hunter -> verifier)
- Cadence: one-time bulk CLI, idempotent re-runs
- Output: vault markdown + TaskNotes kanban; sqlite internal state
- Loom: NOT in v1 email 1 (was rejected as vendor-tier); revisit once positioning warms
- Stack: Python + uv + pytest; OpenRouter claude-haiku-4-5; Playwright + httpx/selectolax
- Email: Python sequencer + Mailtrap dev; production sender + DNS deferred
- Code location: `Tools/prospect-scraper/` (vault subdirectory)
- Email cadence: 3 touches / 8 days
- Volume: ~25 qualified prospects per run

## 13. Open / Future (not blocking v1)
- Production sender choice (Smartlead vs free-tier + own warming) - decide after first live results
- DNS + sending domain/subdomain wiring
- Phase 2 inbound Twitter content engine on shared core
- Scheduling upgrade (cron) once partner #1 lands
- Proxy wiring if any board starts blocking

## 14. The Human Touchpoint (reminder)
The automation gets Utkarsh TO the conversation, warmer and faster. It does not replace it. Every sequence ends at a reply that needs a human (a fit-chat). Building the engine is not a substitute for the conversation.
