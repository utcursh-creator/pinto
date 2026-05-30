---
type: reference
project: content-engine
date: 2026-05-29
status: active
tags: [proof, case-studies, writer-agent, credibility-input]
---

# Proof Bank (credibility input for the Writer Agent)

Real build outcomes the writer agent weaves into content so each piece is PROOF, not
just commentary (per the intertwine-proof-and-distribution model). Distilled from
documented projects in `user_projects.md` + session notes. Utkarsh will add more PRDs
later.

> IMPORTANT: figures marked [CONFIRM] appeared inconsistently in notes or lack a
> documented source. Verify the exact number before it goes into a public post. Do not
> publish an unverified metric.
>
> ANONYMIZATION (Utkarsh rule, 2026-05-29): NEVER publish the client name, the specific
> use-case, or the industry. Describe the problem SHAPE generically. Round all numbers
> (e.g. "around six figures a month", "2-4 hours down to ~10 minutes"). If a metric is
> missing/unconfirmed, ASK Utkarsh to help calculate it before use.

## Builds

### Egroma (construction) - WhatsApp field reporting
- Built: WhatsApp-based field reporting system for construction crews
- Scale: 53 client companies, 292 field workers
- Infra: self-hosted (Hetzner), GDPR-compliant
- Outcome: ~EUR 73K-100K/month operational value / field-labor coordination cost eliminated [CONFIRM exact figure: notes show both 73K and 100K]
- Angle: process automation at real operational scale, compliance-grade

### Marcel Keller (real estate) - AI presentation generator
- Built: AI presentation/proposal generator
- Outcome: 2-4 hours -> ~10 minutes per presentation
- Angle: time compression on a repeated high-effort task

### Poosch / Apex (B2B sales) - SEO report generator
- Built: automated SEO report generator
- Outcome: 45 minutes -> 45 seconds per report; handles 50+ domains
- Angle: ~60x speedup, scale across many accounts

### Aramaz Digital (recruitment) - candidate sourcing
- Built: StepStone candidate sourcing automation (Patchright + FastAPI + Claude eval + Airtable + Recruitee)
- Outcome: replaces ~4 hours/day of manual recruiter sourcing
- Angle: a whole daily human workflow eliminated

### Bildungsfabrik (EdTech) - IHK thesis assistant
- Built: IHK thesis assistant embedded in their LMS
- Outcome: [CONFIRM - no metric documented yet]
- Angle: AI embedded into an existing product/workflow

## Stack (for technical-credibility detail when relevant)
n8n, Make, Supabase, PostgreSQL, Hetzner (self-hosted), Mistral, OpenAI, Pinecone /
vector DBs, Patchright, custom FastAPI scrapers. Enterprise-grade multi-system builds,
not simple Zapier flows.

## Usage rules for the writer agent
- NEVER publish: client name, the specific use-case, or the industry. Describe the PROBLEM SHAPE generically.
- Round numbers ("around six figures a month", "~2 hours to ~10 minutes"). Never publish exact or invented figures.
- If a metric is missing or unconfirmed, ASK Utkarsh to help calculate it before using. Do not guess.
- Weave ONE proof point per piece, matched to the nugget. Lead with the outcome, not the tech stack.

## Anonymized public framings (use these shapes, NOT the identifying details above)
- Egroma -> "a business coordinating a few hundred field workers across dozens of sites; manual reporting was bleeding operations; rebuilt the process and eliminated roughly six figures a month in coordination cost." [CONFIRM the monthly figure]
- Marcel Keller -> "a team hand-building client presentations, 2-4 hours each; automated down to about 10 minutes."
- Poosch -> "a recurring reporting process, ~45 minutes per run across 50+ targets; automated to under a minute."
- Aramas -> "a daily sourcing workflow eating ~4 hours of a specialist's day; automated end to end."
- Bildungsfabrik -> "an AI assistant embedded into an existing education product." [NEED a metric, ask Utkarsh]
