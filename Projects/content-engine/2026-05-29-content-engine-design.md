---
type: spec
project: content-engine
date: 2026-05-29
status: draft-for-review
tags: [spec, content-engine, nuggets, writer-agent, inbound]
---

# Content Engine - Design Spec

A partly-automated content pipeline that turns sources into publish-ready short-form
posts, with Utkarsh as the taste + voice filter at every gate. Goal: inbound
credibility/pipeline among AI/process-automation agency operators + business owners,
peer positioning, not vendor outreach.

## 1. Purpose + Goal
- Build authority + inbound by publishing practitioner content that intertwines PROOF (his real process-automation outcomes, anonymized) with a contrarian frontier-AI FLAVOR, grounded in proven copywriting craft.
- Low bandwidth: the machine (Claude + one code scraper) does heavy reasoning + retrieval; Utkarsh does fast judgment at gates + final voice polish.
- Success (v1): one source flows end-to-end (source -> transcript -> nuggets -> ideas -> draft) and Utkarsh ships a real post with ~20-30 min hands-on time.

## 2. Channel + Content (locked earlier)
- Platform: Twitter/X. Format: text + graphics. NOT video. NOT LinkedIn (platform psychology).
- Content model (C-refined): process-automation PROOF spine + frontier-AI contrarian flavor, intertwined so each piece is both distribution (spreads) and proof (competence). NOT competitor-attacking.
- Tone/craft: governed by `copywriting-framework.md` + `writing-style-analysis.md` + `voice-samples.md`. Anti-template (vary structure every post).

## 3. The Nuggets Pipeline (data flow + gates)
```
SOURCE -> TRANSCRIPT -> NUGGETS -> IDEAS -> DRAFT -> POSTED
          (scraper)    (extract)  (expand) (write)  (+ log)
```
- SOURCE: a URL / PDF / pasted text (one of the 5 curated sources or ad hoc).
- TRANSCRIPT: full raw text of the source (from the scraper, or pasted).
- NUGGETS: subtopics mined from the transcript via the extractor framework. GATE 1: Utkarsh keeps/kills.
- IDEAS: 5-6 angled content ideas per kept nugget, each pre-married to a proof point where relevant. GATE 2: Utkarsh accepts/rejects.
- DRAFT: dense info-architecture for each accepted idea, via the writer agent. GATE 3: Utkarsh edits into final voice.
- POSTED: published to Twitter (manual), logged back to the vault.

## 4. Architecture (hybrid: code for retrieval, Claude for reasoning)
Three components:
- **A. Transcript/source scraper** = production code (the ONLY code). Robust, efficient, tested. No vibecoding.
- **B. content-engine skill** = Claude reasoning (extractor + writer), grounded in the 4 reference files. No code.
- **C. Obsidian Kanban board** = the interface + state. No custom UI.

### 4A. Transcript/Source Scraper (production build)
- Purpose: given a source reference (YouTube URL, article URL, PDF path), return clean full text as a Transcript card. Retrieval only, zero reasoning.
- Sources v1: YouTube (captions via a transcript library; FALLBACK to Whisper audio transcription when captions are missing or auto-caption quality is poor), article/HTML (fetch + readability extraction), PDF (text extract), plain paste (no scraper).
- Gated reports (McKinsey/Menlo/PwC are often PDF-behind-a-form): not auto-fetchable. Expected flow = Utkarsh downloads the PDF, drops it in Sources, scraper ingests it. Do not try to defeat gating.
- **Reuse**: restore the deleted prospect-scraper core from git history (commit before `05f4766`): httpx client + politeness, sqlite, models, CLI, source-module pattern. Repurpose as the transcript scraper foundation instead of rebuilding.
- Requirements: robust error handling, per-source modules, retries, dedup of already-processed sources, output written to the vault Transcripts location + sqlite state. Python 3.12, uv, pytest, TDD. External calls mocked in tests.
- Quality bar: production-level, same rigor as the prospect-scraper build (TDD, audited per task).

### 4B. content-engine skill (the reasoning)
A skill (instructions, not code) that defines HOW Claude does each reasoning stage to standard. Its OPERATING MANUAL is `stage-playbook.md`, which bakes the framework into each stage with per-card schemas and a QA lint at every gate. The skill loads, every run:
- `stage-playbook.md` (operating manual: per-stage process, card schemas, QA lint, anti-repetition, graphics, measurement, proof-mix/cadence)
- `copywriting-framework.md` (persuasion craft + extraction + draft frameworks)
- `writing-style-analysis.md` (his thinking pipeline)
- `voice-samples.md` (his real posts, voice calibration)
- `proof-bank.md` (anonymized proof, usage rules)

Stages the skill governs:
- **Extractor**: transcript -> nuggets. Research-extract not summarize (pull numbers, entities, contradictions); find the MECHANISM per candidate (the One Big Idea, not the stat); rank nuggets by the 4 filters (desire-fit, awareness-distance, freshness-vs-sophistication, decision-relevance). Output: nugget cards with the mechanism + why-it-fits + matched proof point.
- **Idea expander**: each kept nugget -> 5-6 DIFFERENT angles (contradiction / mechanism / unoccupied-space / what-winners-do / etc.), each entering the reader's conversation at a different point, each tagged with awareness stage + a proof point where relevant.
- **Writer agent**: accepted idea -> dense info-architecture draft. Reasoning sequence (entry -> calibrate teach to awareness -> build with specifics+mechanism+soft-PAS -> earned reveal -> land on reader). Targets information density + architecture, NOT voice polish (Utkarsh polishes). Obeys: anonymization rules, no em dashes, anti-template (vary structure), no hard CTA/urgency/hype.

### 4C. Obsidian Kanban board
- Columns: `Sources -> Transcripts -> Nuggets -> Ideas -> Drafting -> Scheduled -> Posted`.
- Each card = a markdown note with frontmatter (type, source, parent nugget, angle, awareness_stage, proof_point, status, date). Lives where TaskNotes/Kanban can render it (tag-based, like the prospect kanban plan).
- Curation = move card / flip status. No app to build.

## 5. Build Order (proves reasoning before code)
- **Phase 1 (no code): content-engine skill + Kanban board + a MANUAL run.** Write the skill (per `stage-playbook.md`), set up the columns, then paste one real source's text and run extractor -> ideas -> draft by hand (Claude) to validate quality + the frameworks against Utkarsh's taste. Tune the skill from his edits. This de-risks the valuable part with zero code.
  - **Acceptance criteria (Phase 1 done):** from 1-2 real sources, the engine yields nuggets Utkarsh agrees are mechanism-grade (not stat-summaries), ideas that are genuinely distinct entry points (not rephrasings), and at least 2-3 drafts he can bring to publish-ready with LIGHT edits (voice his, structure varied, proof woven where relevant, QA-lint clean). If drafts need heavy rewrites, tune the playbook and re-run before touching Phase 2.
- **Phase 2 (code): transcript scraper.** Restore + repurpose the prospect-scraper core; build YouTube + article + PDF retrieval, TDD, audited. Now sources auto-flow into Transcript cards.
- **Phase 3 (later, optional): light auto-feeds + scheduling.** Only if the engine is humming.

## 6. Sources (curated, manual-drop to start)
Stanford HAI AI Index; McKinsey/PwC/BCG/Deloitte enterprise AI; Menlo Ventures + a16z enterprise AI; MIT Sloan Mgmt Review + MIT GenAI studies; Stratechery + Import AI. Research/data that moves business decisions, not model-vs-model news.

## 7. Rules (load-bearing)
- Anonymization: never publish client name / use-case / industry; generic problem-shape; rounded numbers; ask Utkarsh for missing metrics (see proof-bank).
- Voice: writer agent produces dense scaffold; Utkarsh's Gate-3 edit makes it his voice. Not near-zero-edit.
- Anti-template: vary structure every post; frameworks are reasoning inputs, not a stamp.
- No em dashes anywhere.

## 8. Decisions Log (2026-05-29)
- Goal = C-refined (proof spine + frontier flavor, non-attacking). Automation boundary = A (machine reasons + retrieves; human curates + polishes).
- Architecture = A (Claude-orchestrated + Obsidian), with the transcript scraper as production code. No standalone pipeline app, no n8n.
- Writer = info-density + architecture target, grounded in copywriting frameworks + his process; NOT voice-cloning.
- Sources = 5 curated, manual-drop to start. UI = Obsidian Kanban (no custom UI).

## 9. Out of Scope / Future
- Auto-feeds, scheduling, headless runs (Phase 3).
- Video, LinkedIn, newsletter (separate/rejected).
- Auto-posting to Twitter (manual for now).

## 10. Open Items
- Egroma monthly figure + Bildungsfabrik metric (proof-bank [CONFIRM]). Proof-bank expansion (more PRDs from Utkarsh) is a dependency for sustained cadence; 5 builds will repeat fast.
- Exact Kanban plugin mechanics (TaskNotes vs Kanban plugin) confirmed at build.
- Transcript library + Whisper fallback confirmed at scraper build.

## 11. Gap Audit (2026-05-29) - addressed
Deep audit found and CLOSED in `stage-playbook.md`: framework operationalized per stage; per-card schemas (nugget/idea/draft) carrying awareness-stage, sophistication, mass-desire, mechanism, entry-mode, proof-point, format; QA lint before each gate (stat accuracy, anonymization, no em dashes, drop-list, anti-repetition, lands-on-reader); the anti-repetition mechanism (read last 5 cards, vary entry+structure, diversify topic); graphics handling (graphic_need per draft); format decision (single/thread/long by awareness-distance); measurement loop (Posted card performance -> bias future selection toward buyer signal); proof-mix + cadence. Tunable knobs (exact cadence, proof-ratio) settle from the measurement loop.
