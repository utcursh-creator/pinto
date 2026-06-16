---
type: doc
tags: [content-engine]
---

# Content cards

Every card the content engine produces lives here as one markdown file. The
`content-engine` skill writes them; the board `TaskNotes/Views/content-kanban.base`
renders them by `stage`. You curate by reading them and (for keep/kill) telling the
engine, or by editing a card's `stage`/`status`.

## Stages (board columns)
`sources -> transcripts -> nuggets -> ideas -> drafting -> scheduled -> posted`

## Card frontmatter (per stage-playbook)
Common: `type` (nugget|idea|draft), `stage`, `status`, `tags: [content-card, ...]`,
`source`, `parent` (parent card), `date`.
- Nugget adds: `mechanism`, `mass_desire`, `awareness_stage`, `sophistication_note`, `evidence`, `filter_scores`.
- Idea adds: `angle_type`, `entry_mode`, `awareness_stage`, `evidence`, `one_big_idea`, `hook_seed`.
- Draft adds: `entry_mode_used`, `structure_note`, `one_big_idea`, `evidence_woven`, `graphic_spec`, `drop_checks`.

Detailed schemas + the per-stage process: `Projects/content-engine/stage-playbook.md`.
