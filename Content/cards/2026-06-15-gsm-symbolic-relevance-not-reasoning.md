---
type: nugget
stage: nuggets
status: to_review
tags: [content-card, reasoning-failure, contrarian]
source: "arXiv:2410.05229 (GSM-Symbolic, ICLR 2025)"
parent: ""
date: 2026-06-15
mechanism: "An LLM treats every detail in a prompt as a signal to act on, not as something to judge for relevance first. And you cannot patch it with examples: 8 correct in-context worked examples did NOT recover accuracy (Fig 8b). It is a relevance problem, not a reasoning problem."
mass_desire: results
awareness_stage: problem
sophistication_note: "'AI can't reason / stochastic parrot' is BURNED OUT (viral Apple-paper dunk). FRESH: the calibrated mechanism - the model acts on everything you give it, and a 2026 replication showed the scary 65% mostly measured the model making a reasonable inference, which makes the real, narrower finding more credible."
evidence: "external-contrarian:arXiv:2410.05229 (primary, read in full) + external-contrarian:LessWrong-2026-replication (the audit that re-calibrates it)"
filter_scores: "{desire: H, awareness_distance: long, freshness: H, decision_relevance: H}"
---

# Nugget: relevance, not reasoning (GSM-Symbolic)

First real card produced by the content engine (paper-grounded run, 2026-06-15). Seeds
the board and serves as the nugget template.

GSM-NoOp adds one true-but-useless sentence to a math problem; accuracy drops 17.5 pts
(o1-preview) to 65.7 (Phi-3-mini), Fig 8a. The 2026 replication reproduced the drop on
raw data, then audited the clauses: only 12.4% were genuinely irrelevant, and on those
the drop is ~0. The model was making a reasonable bet the detail mattered. The result the
rebuttal does NOT neutralize: 8 in-context worked examples did not fix it (Fig 8b), so you
design around it. For anyone wiring an LLM into real, messy business data full of stray
plausible-looking fields, that is the whole ballgame: control what reaches the model.

Full draft + 6 angles: `Projects/content-engine/cards-gsm-symbolic.md`.
