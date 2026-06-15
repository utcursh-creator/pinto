# Content Engine - Plan 1: Skill + Kanban (no code)

> Execute with superpowers:executing-plans or inline. Checkbox (`- [ ]`) steps.

**Goal:** Package the validated engine as an invokable `content-engine` skill and set up the Obsidian Kanban board, so Utkarsh runs the pipeline repeatedly and curates in the vault. Zero code (the code is Phase 2).

**Why this first:** the reasoning engine is already proven (4 runs). What is missing is repeatable invocation + a place for the cards to live. This closes that with skill-authoring + an Obsidian board.

**Reference files the skill consumes (already written):** `utkarsh_braindump.md` (territory + sources), `stage-playbook.md` (operating manual), `copywriting-framework.md`, `writing-style-analysis.md`, `voice-samples.md`, `proof-bank.md`.

---

## Task 1: Write the `content-engine` skill

**Files:**
- Create: `.claude/skills/content-engine/SKILL.md`

- [ ] **Step 1: Author SKILL.md.** It must:
  - Frontmatter: name `content-engine`, a description that triggers on "run the content engine / make content from <source> / turn this into posts".
  - INPUTS: instruct to load all 6 reference files from `Projects/content-engine/` at the start of every run (territory, stage-playbook, craft, style, voice, proof).
  - PROCESS: run the stage-playbook pipeline. For a source (URL / paper / pasted text):
    1. Get the text (Phase 1: paste or WebFetch; Phase 2 scraper replaces this).
    2. EXTRACTOR -> nugget cards (with dynamic research per the playbook: reach primary papers via arXiv/Semantic Scholar/web, find the mechanism, attach evidence internal/supporting/contrarian, score the 4 filters).
    3. Present nuggets; wait for keep/kill (GATE 1).
    4. EXPANDER -> 5-6 idea cards for kept nuggets (GATE 2).
    5. WRITER -> dense draft card + graphic_spec for accepted ideas (GATE 3 = Utkarsh edits).
  - DELEGATION: for research-heavy runs, dispatch a sub-agent (opus) with the reference files + source, returning the cards (this is how the validated runs worked).
  - OUTPUT: write each card as a markdown file into the Kanban folder (Task 2) with the stage-playbook frontmatter; move cards across columns by status.
  - RULES: enforce the QA lint (stat accuracy + primary-source verification, anonymization, no em dashes, drop-list, anti-repetition, lands-on-reader) before any draft reaches GATE 3.
  - ANTI-REPETITION: before drafting, read the last 5 cards in Drafting/Scheduled/Posted; vary entry mode + structure + topic.

- [ ] **Step 2: Verify the skill loads.** Run `/content-engine` (or trigger phrase) with a pasted short source; confirm it loads the references and produces nugget cards. No code to test; this is a smoke check of the skill instructions.

- [ ] **Step 3: Commit.** `git add .claude/skills/content-engine/SKILL.md && git commit -m "feat: content-engine skill (pipeline orchestration)"`

---

## Task 2: Set up the Obsidian Kanban board

**Files:**
- Create: `Content/` folder (the card store) with subfolders or a flat store + status frontmatter
- Create: a board view (TaskNotes base OR Kanban-plugin board) filtering content cards by status

- [ ] **Step 1: Decide the card store.** Create `Content/cards/` for all engine cards (nugget/idea/draft). Each card = one markdown file, frontmatter per stage-playbook (type, status, parent, mechanism/angle/evidence/graphic_spec, etc.), tag `content-card`.

- [ ] **Step 2: Create the board.** Columns = the pipeline stages: `Sources -> Transcripts -> Nuggets -> Ideas -> Drafting -> Scheduled -> Posted`. Implement as a TaskNotes base (filter `file.hasTag("content-card")`, group by `status`) mirroring `TaskNotes/Views/kanban-default.base`, OR a Kanban-plugin board if simpler. Save under `TaskNotes/Views/content-kanban.base` (or `Content/board.md`).

- [ ] **Step 3: Smoke test the board.** Drop 2-3 dummy cards with different `status` values; confirm they render in the right columns and that moving a card (changing status) moves it across columns.

- [ ] **Step 4: Commit.** `git add Content/ TaskNotes/Views/content-kanban.base && git commit -m "feat: content engine Kanban board"`

---

## Task 3: First real end-to-end run through the board

- [ ] **Step 1: Run the skill on one real source** (a paper or report in the territory). Let it produce nugget cards into `Content/cards/` at status `to_review` (Nuggets column).
- [ ] **Step 2: Curate.** Utkarsh keeps/kills nuggets (Gate 1), the skill expands kept ones to ideas (Ideas column), Utkarsh accepts (Gate 2), the writer drafts (Drafting column).
- [ ] **Step 3: Confirm the loop.** A draft card sits in Drafting, ready for Utkarsh's voice polish. Verify the whole flow happened IN the vault via the board.
- [ ] **Step 4: Tune.** Note any playbook gaps surfaced by the real run; fix `stage-playbook.md`. Commit any tuning.

---

## Definition of Done (Plan 1)
- `/content-engine` skill is invokable and runs the pipeline, loading the 6 reference files.
- Obsidian Kanban board renders content cards by status; moving a card works.
- One real source has flowed source -> nuggets -> ideas -> a draft card, curated through the gates in the vault.
- No code yet (paper-retrieval scraper + graphics generator = Plan 2).

## Audit checklist (skeptical, before Plan 2)
- Does the skill actually LOAD all 6 reference files each run, or drift to freelancing? (Check a run's behavior against the playbook.)
- Does anti-repetition actually read prior cards, or is it nominal? Verify it varies entry/structure across 2 consecutive drafts.
- Are draft cards passing the QA lint (esp. primary-source verification) before Gate 3, or slipping through?
- Is the board genuinely usable for curation, or is editing frontmatter friction? If friction, simplify the card schema.
