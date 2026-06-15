---
type: pipeline-run
project: content-engine
date: 2026-06-15
status: to_review
source_paper: "GSM-Symbolic (arXiv:2410.05229), ICLR 2025"
tags: [content-engine, nugget, idea, draft, reasoning-failure, contrarian, literature-grounded]
---

# Pipeline Run: GSM-Symbolic (reasoning fragility)

Paper-grounded demonstration run. Source is the primary literature, not press coverage.
Primary paper read in full (PDF, all 11 pages incl. figures 7 and 8). Honest critique
sourced from the 2026 replication (LessWrong) which materially re-calibrates the headline.

Anti-repetition check: prior published pieces all orbit the "deployment/adoption gap" +
business surveys (PwC/McKinsey). This run is fresh territory (reasoning-failure
literature, technical). Banned openers avoided ("If you are a domain expert" / "I like
reading surveys"). No deployment-gap topic.

---

## STAGE 1 - NUGGETS

### Nugget A (PRIMARY) - the in-context patch does not work

```yaml
type: nugget
source: arXiv:2410.05229 (GSM-Symbolic, Mirzadeh/Bengio/Farajtabar et al., Apple, ICLR 2025)
status: kept
mechanism: An LLM treats every detail in a prompt as a signal to act on, not as something to judge for relevance first; so a fact that should be ignored gets converted into an operation. And this is not a prompting bug you can fix with examples - feeding the model the exact correct reasoning chain as 8 in-context shots does NOT recover the accuracy.
mass_desire: results (builds that hold up in production, not demos)
awareness_stage: problem
sophistication_note: "AI can't reason / stochastic parrot" is BURNED OUT (viral Apple-paper coverage flattened it into a dunk). What is FRESH is the calibrated mechanism - not "it can't reason" but "it acts on everything you give it, and you can't patch that with more examples" - plus the honest fact that the scary 65% headline mostly measured the model making a reasonable inference, which makes the real, narrower finding more credible, not less.
evidence: external-contrarian:arXiv:2410.05229 (primary) + external-contrarian:LessWrong-2026-replication (the audit that re-calibrates it, https://www.greaterwrong.com/posts/Ze4C99Dasj74YKCFh)
filter_scores: {desire: H, awareness_distance: long, freshness: H, decision_relevance: H}
```

**Raw extracted facts (exact, from the primary paper):**
- GSM-NoOp experiment (Sec 4.4, Fig 7): take a grade-school math word problem and add ONE clause that looks relevant but changes nothing. Their example: "Oliver picks 44 kiwis Friday, 58 Saturday, on Sunday double Friday, **but five of them were a bit smaller than average**. How many kiwis does Oliver have?" The correct answer ignores the size of the kiwis (190). Both o1-mini and Llama3-8B subtract the 5 "smaller" kiwis and answer 185.
- Per-model accuracy DROP on GSM-NoOp vs the clean set (Fig 8a, exact): o1-preview -17.5, o1-mini -29.1, GPT-4o -32.0, Mathstral-7B -28.3 to -40.3, Llama3-8B-instruct -57.4, Phi-3-medium -57.8, Gemma2-9B -63.0, Phi-3-mini -65.7 (the "up to 65%" headline). More recent/larger models drop LESS but still drop.
- THE DEEPEST RESULT (NoOp-Symb, Fig 8b): they gave the model 8 in-context examples of the SAME question WITH the correct reasoning chain, then asked a numbers-only variant with an inconsequential clause. For Llama3-8B accuracy stayed at ~18.6 / 19.6 / 19.2 vs 76.0 with normal GSM8K shots. The fix you would reach for first (show it worked examples) does not close the gap. Paper: "This suggests deeper issues in their reasoning processes that cannot be alleviated by in-context shots."
- Paper's central claim (verbatim, abstract): "current LLMs are not capable of genuine logical reasoning; instead, they attempt to replicate the reasoning steps observed in their training data."

**The honest critique (re-calibration, mined from the 2026 replication):**
- A March 2026 replication (GPT-4o, Claude Opus 4.6, Claude Haiku 4.5) reproduced almost the exact original drop on the UNAUDITED set (GPT-4o again ~94.9% -> ~63.0%, about a 32-point fall).
- Then they audited the "irrelevant" clauses with two independent labelers. Only 117 of 945 (12.4%) were judged genuinely irrelevant; the auditors disagreed heavily on the rest (kappa = 0.32). Example of a clause that is NOT cleanly irrelevant: "although 3 of Qasim's baskets were later reviewed and confirmed as 2-pointers instead of 3-pointers" - that plausibly DOES change a points total.
- On the cleanly-irrelevant subset, the drop was 0-2 points, statistically indistinguishable from zero.
- Their read: the model was "making a reasonable inference that the confounders ... are real signals to adjust its calculations." Not noise-blindness. A reasonable-but-wrong bet that the detail mattered.

**Why this is the nugget, and why it fits U's audience (agency operators + business owners building agentic systems):** The viral story ("AI can't reason") is both burned out and partly wrong. The TRUE, narrower, durable finding is more useful: an LLM does not first decide whether a piece of input deserves to affect the output. It tends to act on whatever you put in front of it. The kiwi clause and the audit both point at the same mechanism from opposite directions. And the NoOp-Symb result is the part the rebuttal does NOT neutralize: you cannot reliably train this out of a single prompt with examples. For someone wiring an LLM to real business data full of stray, plausible-looking fields, that is the whole ballgame.

### Nugget B (secondary) - same question, different numbers, different competence

```yaml
type: nugget
source: arXiv:2410.05229 (GSM-Symbolic, Sec 4.1-4.3)
status: kept
mechanism: Model "accuracy" on a benchmark is a single draw from a distribution, not a fixed property. Swap only the NUMBERS in a question (same logic, same steps) and accuracy moves; the original benchmark score tends to sit at the optimistic top edge of that distribution, which is what contamination looks like.
mass_desire: not-wasting-spend (do not buy a model on a headline benchmark)
awareness_stage: solution
sophistication_note: "benchmarks are gamed / contaminated" is semi-known; the FRESH part is the quantified shape - a single model's accuracy spans ~15 points just from re-rolling names and numbers, and the published GSM8K score sits above the mean for 21 of 25 models.
evidence: external-contrarian:arXiv:2410.05229
filter_scores: {desire: M, awareness_distance: medium, freshness: M, decision_relevance: H}
```

**Raw facts:** GSM-Symbolic builds 50 templates from GSM8K, re-rolls names/values, runs 50 samples each. A single model's accuracy spread across re-rolls: Gemma2-9B >12 points, Phi-3.5-mini ~15 points. Changing only NAMES barely moves accuracy; changing NUMBERS moves it more; changing both moves it most (Fig 4). The original GSM8K score sits more than 1 SD above the GSM-Symbolic mean for 21 of 25 models (Fig 2) - consistent with test data leaking into training. As difficulty rises (GSM-M1 -> Symbolic -> P1 -> P2) accuracy falls and variance grows monotonically; e.g. Phi-3-medium 89.0 -> 82.5 -> 75.8 -> 53.1 (Fig 6).

(Nugget B is real and shippable but Nugget A is the stronger pick - it has the sharper mechanism, the live decision-relevance for agent builders, and the built-in honest critique. Ideas + draft below are for Nugget A.)

---

## STAGE 2 - IDEAS (6 distinct angles for Nugget A)

### Idea A1 - reframe: it is not a reasoning problem, it is a relevance problem
```yaml
type: idea
parent_nugget: A
status: to_review
angle_type: reframe
entry_mode: contradiction
mass_desire: results
awareness_stage: problem
evidence: external-contrarian:arXiv:2410.05229
one_big_idea: The famous "AI can't reason" paper does not actually show models can't reason; it shows they don't decide what is worth reasoning about. That distinction changes what you defend against.
hook_seed: The paper everyone quoted to prove AI can't think showed something more useful, and almost nobody repeated it.
```

### Idea A2 - mechanism: the model acts on everything you give it
```yaml
type: idea
parent_nugget: A
status: to_review
angle_type: mechanism
entry_mode: shared-curiosity
mass_desire: results
awareness_stage: solution
evidence: external-contrarian:arXiv:2410.05229
one_big_idea: A human reads a problem and silently throws away the parts that don't matter. An LLM doesn't do the throwing-away step. Every clause is a candidate instruction.
hook_seed: Add one true-but-useless sentence to a math problem and a frontier model's accuracy can fall by a third.
```

### Idea A3 - what-winners-do: the fix you reach for first does not work
```yaml
type: idea
parent_nugget: A
status: to_review
angle_type: what-winners-do
entry_mode: tension
mass_desire: results
awareness_stage: solution
evidence: external-contrarian:arXiv:2410.05229
one_big_idea: When the model goes wrong on a stray detail, the instinct is "give it examples." The paper tested exactly that - 8 worked examples of the same question - and the error survived. The real fix is upstream: control what reaches the model.
hook_seed: They showed the model the correct worked example eight times. It still got the next one wrong.
```

### Idea A4 - identification: this is the bug in your pipeline you blamed on the prompt
```yaml
type: idea
parent_nugget: A
status: to_review
angle_type: identification
entry_mode: identity-filter
mass_desire: results
awareness_stage: problem
evidence: external-contrarian:arXiv:2410.05229
one_big_idea: If your agent occasionally does something insane on a real record, it is probably not a bad prompt. It is the model treating a stray field in your data as an instruction.
hook_seed: Your agent that works in the demo and breaks on real data is not badly prompted. It is reading a field you forgot was there.
```

### Idea A5 - unoccupied-space: the honest version is the moat
```yaml
type: idea
parent_nugget: A
status: to_review
angle_type: unoccupied-space
entry_mode: contradiction
mass_desire: niche
awareness_stage: most-aware
evidence: external-contrarian:arXiv:2410.05229 + external-contrarian:LessWrong-2026-replication
one_big_idea: The viral take ("AI can't reason") and the rebuttal ("the test was unfair") are both half-right. The audited finding sits in between and is the one worth building around - and almost no one is telling clients the in-between version.
hook_seed: A 2026 re-run of the famous paper found the scary number mostly measured the model being reasonable. That makes the real finding more useful, not less.
```

### Idea A6 - contradiction: the better the model, the less it saves you here
```yaml
type: idea
parent_nugget: A
status: to_review
angle_type: contradiction
entry_mode: tension
mass_desire: not-wasting-spend
awareness_stage: solution
evidence: external-contrarian:arXiv:2410.05229
one_big_idea: A stronger model shrinks the problem (o1-preview drops 17 points where small models drop 65) but does not remove it. You cannot buy your way out of this with a bigger model; you design around it.
hook_seed: Upgrading the model cut the failure in half. It did not make it go away. That gap is a design problem, not a budget problem.
```

QA Gate 2: all 6 are different entry points (reframe / mechanism / what-winners-do / identification / unoccupied-space / contradiction), not rephrasings. Each carries the contrarian-literature evidence. **Strongest: A1 reframe**, because it does the most work for U's audience - it takes the take they have already heard, corrects it with the actual paper, and hands them a decision they can act on. The draft below builds A1 and folds in the A3 (in-context patch fails) and A4 (this is your pipeline bug) beats, because together they make the reveal land on the reader.

---

## STAGE 3 - DRAFT

```yaml
type: draft
parent_idea: A1
status: drafting
entry_mode_used: contradiction
structure_note: open on the gap between the viral claim and the real finding -> teach the kiwi experiment plainly -> the number -> the honest rebuttal that re-calibrates it -> the deeper result the rebuttal does not touch -> reframe (relevance not reasoning) -> land on the reader's own pipeline
one_big_idea: The famous paper does not prove AI cannot reason; it shows models do not decide what is worth reasoning about - and you cannot patch that with examples, so you design around it.
evidence_woven: external-contrarian:arXiv:2410.05229 (primary, read in full) + external-contrarian:LessWrong-2026-replication (the audit)
graphic_spec: "Horizontal bar chart, single series. Title: 'Accuracy drop when one useless-but-true sentence is added to a math problem (GSM-NoOp, arXiv:2410.05229).' Bars (percentage-point drop, plot as negative or as magnitude with a clear axis label 'accuracy lost'): o1-preview 17.5, o1-mini 29.1, GPT-4o 32.0, Mathstral-7B 28.3, Llama3-8B 57.4, Phi-3-medium 57.8, Gemma2-9B 63.0, Phi-3-mini 65.7. Sort descending by magnitude. Annotate a single reference line / caption: 'A March 2026 re-run found most of this gap disappears once you keep only the sentences that are genuinely irrelevant - the models were treating the extra detail as a real signal.' Clean, branded, no 3D. Numbers exact to Fig 8a."
drop_checks: passed
```

**Body (dense draft - information architecture, U adds final voice):**

Last year a paper out of Apple got passed around as the proof that AI cannot actually reason.

The setup was simple enough to explain in one line.

Take a grade-school math problem. Add a single sentence that is true but useless. Watch the model fall apart.

Their example: Oliver picks 44 kiwis on Friday, 58 on Saturday, and on Sunday he picks double what he picked Friday. One extra detail: five of Sunday's kiwis were a bit smaller than average.

The size of the kiwis has nothing to do with how many he has.

A grade-schooler ignores it. The model subtracts the five small ones and gets the wrong number.

Across the models they tested, adding that kind of throwaway sentence dropped accuracy by anywhere from about 17 points on the strongest model up to 65 points on a small one.

That is the chart that went viral. "AI can't reason."

Here is the part that almost nobody passed along.

This year someone re-ran it carefully. They reproduced the scary drop on the raw test set. Then they did the obvious thing the original skipped: they actually checked whether the "irrelevant" sentences were irrelevant.

Most of them were not.

A sentence like "three of the baskets were later re-counted as two-pointers instead of three-pointers" is not noise. That genuinely could change the total. When two independent reviewers tried to sort the truly-useless sentences from the arguably-relevant ones, they barely agreed with each other.

Once you keep only the sentences that are actually, cleanly irrelevant, the drop nearly vanishes. Zero to two points.

So the headline was wrong in the way headlines usually are.

But sit with what the corrected version is actually saying, because it is more useful than the dunk.

The model was not failing to reason. It was reading every detail you handed it and assuming it was there for a reason. It treated "five were smaller" and "re-counted as two-pointers" the same way: as a signal it was supposed to act on.

That is not a reasoning problem. It is a relevance problem.

A person reads a problem and silently deletes the parts that do not matter before they start. That deletion step is invisible, automatic, and it is the thing the model does not reliably do.

Now the result the rebuttal does not touch, and the one that should change how you build.

The original authors tried to fix the failure the way any of us would. They gave the model eight worked examples of the exact same question, correct reasoning shown each time, and then asked one more variation.

The model still got it wrong. Accuracy stayed near the floor.

Showing it the answer eight times did not teach it to ignore the useless sentence.

That is the line to keep. The first move you reach for when an AI does something dumb is "give it examples." On this failure mode, more examples did not close the gap.

Which tells you where the fix actually lives.

If you are wiring a model into a real business, your data is full of true-but-useless detail. Stray fields, leftover notes, a status flag from three systems ago, a comment someone left in a cell in 2021. To you it is obviously irrelevant. To the model it is one more signal to act on.

The agent that works perfectly in your demo and then does something insane on a real customer record is usually not badly prompted. It is reading something you forgot was in the row.

So the work is not "write a smarter prompt" and it is not "wait for a smarter model." A bigger model shrinks this (17 points instead of 65) but does not erase it.

The work is upstream. Decide what reaches the model. Strip the record down to the fields that matter before it ever hits the prompt. Treat relevance as something you own, not something the model figures out.

The people who read the viral version think the lesson is "AI can't be trusted to think."

The people who read the actual paper know the lesson is narrower and more actionable: the model will act on whatever you put in front of it, so the leverage is in what you choose to put there.

That gap between the two readings is where the reliable systems get built.

Save this if you are putting an AI agent anywhere near real, messy data.

QA LINT (writer self-check):
- No hard CTA / no urgency / no scarcity / no hype-superlatives / no clickbait open loop: PASS (soft "Save this" only; the open is a real contradiction with the payoff delivered in-post).
- Anonymization: PASS (no client/use-case/industry; the only "your pipeline" reference is generic; no proof-bank metric used - this is a pure mechanism piece, which the proof-mix cadence explicitly allows).
- No em dashes: PASS (hyphens/colons only).
- Every number traces to source: PASS - 17.5 / 29.1 / 32.0 / 57.4 / 57.8 / 63.0 / 65.7 from arXiv:2410.05229 Fig 8a; "up to 65%" is the paper's own phrasing; 12.4% audited-irrelevant, ~94.9->63.0, kappa=0.32, 0-2pt residual, and the 8-shot-fails result from the primary paper (Fig 8b) + the 2026 replication.
- Anti-repetition: PASS - entry_mode (contradiction) and structure differ from the last 5 cards; topic is reasoning-failure literature, NOT the deployment/adoption gap; banned openers avoided.
- Lands on the reader, not a pitch: PASS (ends on "what you choose to put there" + the reader's own messy-data pipeline).
