---
name: content-engine
description: >
  Run Utkarsh's content engine: turn a source (research paper, report, article, talk, or
  pasted text) into publish-ready short-form content for Twitter - mechanism-grade nuggets,
  distinct angles, and dense drafts grounded in his territory, his voice, and proven
  copywriting craft. Use when the user says "run the content engine", "make content from
  <source>", "turn this into posts/nuggets", or drops a source/paper to process into content.
---

# Content Engine

Turns one source into curated, publish-ready content, with Utkarsh as the taste + voice
filter at every gate. The machine does the heavy reasoning + research; he does fast
judgment + final voice polish. This skill orchestrates the pipeline; the detailed per-stage
mechanics live in the reference files below.

## Load these every run (from `Projects/content-engine/`)
1. `utkarsh_braindump.md` - the TERRITORY (contrarian + frontier + security + long-horizon) + the source priorities (primary research papers are the deepest layer: arXiv, Semantic Scholar, OpenReview, Papers with Code; AI / anti-AI-critical / experiments / behavior).
2. `stage-playbook.md` - the OPERATING MANUAL: per-stage process, card schemas, QA lint, dynamic research, anti-repetition, graphics, measurement. Follow it exactly.
3. `copywriting-framework.md` - persuasion craft (Schwartz awareness/sophistication, Collier, Sugarman, specificity, earned reveal, drop-list).
4. `writing-style-analysis.md` - his cognitive process (not a template).
5. `voice-samples.md` - his real posts (voice/structure calibration).
6. `proof-bank.md` - anonymized build proof + anonymization rules.

Do not freelance. If a run drifts from the playbook, stop and re-read it.

## Pipeline (write a card to the board at each stage; gates are Utkarsh's)
```
SOURCE -> TRANSCRIPT -> NUGGETS -> [GATE 1 keep/kill] -> IDEAS -> [GATE 2 accept/reject] -> DRAFT -> [GATE 3 edit] -> SCHEDULED -> POSTED
```
1. **Get the source text.** Phase 1: pasted text, or WebFetch a URL, or fetch a paper (arXiv/Semantic Scholar). (Phase 2's scraper will automate this. For papers, read the PRIMARY paper, not press coverage; verify exact numbers from the actual PDF.)
2. **EXTRACTOR -> nuggets.** Research-extract (numbers, entities, contradictions), find the MECHANISM (not the stat), DYNAMIC RESEARCH for evidence (internal proof, external supporting, or external contrarian - there is always an angle; reach primary papers), score the 4 filters. Write nugget cards.
3. **GATE 1:** present nuggets, Utkarsh keeps/kills.
4. **EXPANDER -> 5-6 ideas** per kept nugget (genuinely different entry points). Write idea cards.
5. **GATE 2:** Utkarsh accepts/rejects ideas.
6. **WRITER -> dense draft** for accepted ideas (entry -> calibrate to awareness -> build with specifics + mechanism -> earned reveal -> land on reader). Target information density + architecture, NOT voice polish. Include `graphic_spec`. Write draft card.
7. **GATE 3:** Utkarsh edits into final voice, then schedules/posts. Capture performance on the Posted card (measurement loop).

## When to delegate to a sub-agent
For research-heavy runs (papers, multi-source, long-horizon), dispatch an opus sub-agent with: the 6 reference file paths + the source + "you ARE the content engine, follow the stage-playbook". It returns the cards. This is how the validated runs worked and keeps the main context clean. For a quick single paste, run inline.

## Where cards go
Write each card as a markdown file in `Content/cards/` with the stage-playbook frontmatter (include `stage:` = sources|transcripts|nuggets|ideas|drafting|scheduled|posted, `status:`, and the tag `content-card`). The Kanban board (`TaskNotes/Views/content-kanban.base`) renders them by stage. Move a card by updating its `stage`.

## QA lint (enforce before any draft reaches GATE 3)
- STAT ACCURACY: every number/claim traces to the source or a cited primary paper. Verify from the actual paper, not coverage. Flag unverified claims; never ship them. (Contrarian content dies on one fabricated claim.)
- ANONYMIZATION: no client name / use-case / industry; rounded proof numbers.
- NO EM DASHES anywhere (hyphens/colons).
- DROP-LIST: no hard CTA, no urgency/scarcity, no hype/superlatives, no clickbait.
- ANTI-REPETITION: read the last 5 cards in Content/cards/ at stage drafting/scheduled/posted; vary entry mode + structure + topic. Avoid his used openers ("If you are a domain expert", "I like reading surveys") and the burned deployment/adoption-gap topic.
- LANDS ON THE READER, not a pitch.

## Output to the user
At each gate, show the cards concisely (the mechanism / the angle / the draft), not raw dumps. End a full run with a short self-critique (strong / weak / what Utkarsh must fix), and flag any claim that still needs his primary-source verification before publishing.
