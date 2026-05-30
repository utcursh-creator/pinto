---
type: reference
project: content-engine
date: 2026-05-29
status: active
tags: [content-engine, skill, stage-playbook, card-schema, qa]
---

# Stage Playbook (the content-engine skill's operating manual)

How the copywriting craft (`copywriting-framework.md`) + his thinking pipeline
(`writing-style-analysis.md`) get BAKED INTO each stage, what each card must capture so
the framework flows downstream instead of being re-guessed, and the QA gate at each step.
Loaded by the content-engine skill on every run.

## How the two frameworks combine (reconciliation)
- `writing-style-analysis.md` = the COGNITIVE process (absorption -> system-mapping -> editorial judgment -> framing -> build -> reveal -> land). This is HOW Utkarsh thinks.
- `copywriting-framework.md` = the PERSUASION craft (enter the conversation, channel desire, awareness/sophistication, specificity, slippery slide, earned reveal, drop-list). This is WHY it lands.
- They are complementary layers, not competing. The cognitive process decides WHAT is worth saying; the craft decides HOW to make it land. The writer applies both; neither is a template.

## Cross-cutting rules (every stage)
- **Stat accuracy**: never fabricate, round-up, or misattribute a number. Every figure traces to the transcript or the proof-bank. If unsure, flag, do not publish.
- **Anonymization**: never client name / use-case / industry; generic problem-shape; rounded proof numbers (proof-bank rules).
- **No em dashes** anywhere. Hyphens/colons only.
- **Anti-repetition** (his cardinal rule): before drafting, read the last 5 cards in Drafting+Scheduled+Posted; record their entry_mode, structure_note, and topic; the new piece MUST differ on entry mode AND structure, and should not re-orbit a recently-used topic (see README published-content tracker; current warning: stop orbiting the "deployment/adoption gap").
- **Drop-list** (organic, not sales letter): no hard CTA, no manufactured urgency/scarcity, no hype/superlatives, no clickbait open loops, no rigid repeated formula.

## Dynamic research (the system is a smart, active researcher, NOT a transcript summarizer)
The engine does not work only from the one transcript. At extraction AND expansion it actively QUERIES for more: web search + the curated sources, to find supporting data, the contrarian paper that argues the opposite, the number that confirms or breaks a claim. The logic is dynamic per nugget: reason about what evidence and angle THIS nugget needs, then go get it.
**There is ALWAYS an angle.** If no internal build-proof fits a nugget, do not drop it, re-angle it:
- find external research that SUPPORTS the claim (data, a study), or
- find a credible source AGAINST the claim and run it as a contrarian angle (a paper/data that contradicts the prevailing view is itself a strong post).
A nugget is never discarded for lacking a proof tie. Every nugget carries SOME evidence: internal proof, external supporting, or external contrarian.

**Depth + horizon + precision (per `utkarsh_braindump.md` territory):**
- LONG-HORIZON, not current-year: pull 2030+/2050 outlooks, trajectories, forecasts. Current-year-only data is too weak for this territory.
- TECHNICAL-DEEP: frontier research/architecture (arXiv-grade), not business summaries.
- FACTUAL PRECISION is existential: contrarian content dies on ONE fabricated claim. Every specific (a strike, a kidnapping, a model spec, a stat) needs a PRIMARY source before it enters a nugget or draft. Flag unverified claims; never let them through QA.
- CONTRARIAN INVERSION: take the consensus take, find the sharper/truer inversion (e.g. "redundancy makes you safe" -> "redundancy multiplies the attack surface while solving the least likely failure mode").

## STAGE 1 - EXTRACTOR (transcript -> nuggets)
Process (RMBC-R + Schwartz + his absorption/system-mapping):
1. Research-extract: pull every hard number, sample size, named entity, dollar figure, and especially CONTRADICTIONS (data that fights the prevailing narrative). Contradiction = raw angle ore.
2. Find the MECHANISM for each candidate: the underlying WHY nobody has named. The mechanism, not the stat, is the nugget. A report yields ~10 stats but only 2-3 real mechanisms.
3. Score + rank on the 4 filters: desire-fit, awareness-distance, freshness-vs-sophistication, decision-relevance. Drop burned-out claims.
4. Evidence/angle pass (DYNAMIC RESEARCH): for each surviving nugget, attach the evidence that best angles it. Internal build-proof if one fits; else actively query (web + curated sources) for external SUPPORTING research, or a credible source AGAINST the claim to run as a contrarian angle. Never leave a nugget without an angle.

Nugget card frontmatter:
```yaml
type: nugget
source: <source id/url>
status: to_review            # to_review|kept|killed
mechanism: <the One Big Idea / underlying why, one line>
mass_desire: results|niche|not-wasting-spend|<other>
awareness_stage: unaware|problem|solution|product|most-aware
sophistication_note: <what claims are burned out here; what is fresh>
evidence: internal-proof:<id> | external-supporting:<source> | external-contrarian:<source>   # ALWAYS one, never none; dynamically researched if no internal proof fits
filter_scores: {desire: H/M/L, awareness_distance: short/long, freshness: H/M/L, decision_relevance: H/M/L}
```
Body: the raw extracted facts/contradictions + the mechanism stated + why it fits the audience.
QA before Gate 1: every nugget has a named mechanism (not just a stat); attaches to a mass desire; burned-out claims removed; numbers accurate to transcript.

## STAGE 2 - EXPANDER (kept nugget -> 5-6 ideas)
Process: generate 5-6 GENUINELY DIFFERENT angles, each entering the reader's conversation at a different point. Angle types to draw from: contradiction, mechanism, unoccupied-space ("where the gap is"), what-winners-do, identification (mirror lived experience), reframe. Each idea: assign awareness stage, format, and a proof tie where one fits.

Idea card frontmatter:
```yaml
type: idea
parent_nugget: <nugget id>
status: to_review            # to_review|accepted|rejected
angle_type: contradiction|mechanism|unoccupied-space|what-winners-do|identification|reframe
entry_mode: identity-filter|shared-curiosity|contradiction|tension
mass_desire: results|niche|not-wasting-spend|<other>
awareness_stage: unaware|problem|solution|product|most-aware
evidence: internal-proof:<id> | external-supporting:<src> | external-contrarian:<src>
one_big_idea: <one line>
hook_seed: <a candidate first line that enters the conversation>
```
QA before Gate 2: the 5-6 are different ENTRY POINTS, not rephrasings; each scored; strongest flagged; each carries an evidence angle (internal proof or researched supporting/contrarian).

## STAGE 3 - WRITER (accepted idea -> dense draft)
Process = the draft-structure reasoning sequence (varies per idea, never a template):
1. Entry: open inside the reader's existing thought via the idea's entry_mode. First line earns the second (Sugarman).
2. Calibrate teach to awareness_stage: new concept -> teach via analogy first; familiar -> move fast to the system.
3. Build with specifics + mechanism, soft-PAS the tension: lay the hard numbers, show the broken system, let the reader feel the cost (no manufactured urgency), stack proof so each claim raises belief.
4. Earned reveal: name the one_big_idea only after the evidence makes it feel discovered.
5. Land on the reader: end at the gap/unoccupied-space/the bet they now see differently. Soft signal only ("Save this"), never "DM me".
Target = INFORMATION DENSITY + ARCHITECTURE, not voice polish. Utkarsh's Gate-3 edit adds voice.

Draft card frontmatter:
```yaml
type: draft
parent_idea: <idea id>
status: drafting             # drafting|scheduled|posted
entry_mode_used: <mode>
structure_note: <one line describing the shape, for anti-repetition tracking>
one_big_idea: <one line>
evidence_woven: internal-proof:<id> | external-supporting:<src> | external-contrarian:<src>
graphic_spec: <chart type + the exact data to plot | diagram description | none>   # rendered programmatically
drop_checks: passed          # set after QA lint
```
Body: the dense draft (the info-architecture).

QA LINT before Gate 3 (the writer self-checks, reports pass/fail per item):
- No hard CTA, no urgency/scarcity, no hype/superlatives, no clickbait loop.
- Anonymization clean (no client/use-case/industry; rounded numbers).
- No em dashes.
- Every number traces to the transcript or proof-bank (stat accuracy).
- structure_note + entry_mode differ from the last 5 cards (anti-repetition); topic not re-orbiting a recent one.
- Ends on the reader, not a pitch.

## GRAPHICS (programmatic, code, no manual creation)
Graphics are generated ENTIRELY PROGRAMMATICALLY by a code library. The draft sets `graphic_spec` (chart type + the exact data to plot, or a diagram description). A graphics generator renders a clean, consistently-branded image from that spec:
- charts + data-viz: a plotting library (e.g. matplotlib/plotly) re-plots the nugget's real numbers cleanly.
- system-maps / diagrams: a diagram library renders flows (e.g. the circular Nvidia->OpenAI->Oracle money map).
This is a CODE component, built in the code phase alongside the transcript scraper. Numbers come from the nugget evidence and must be accurate to source (stat-accuracy rule). No screenshots, no manual graphic-making.

## MEASUREMENT LOOP (so the engine learns)
Posted card captures, a few days after posting:
```yaml
performance: {saves: n, replies: n, dms: n, profile_visits: n, qualified_signal: y/n}
```
Periodic review (weekly): read Posted performance, bias future nugget/angle selection toward what drew BUYER signal (saves, DMs, qualified replies), not vanity likes. This is the read-the-data-and-optimize loop.

## PROOF MIX + CADENCE
- Not every piece needs proof. Aim for roughly half the pieces to weave a proof point; the rest are pure mechanism/insight (distribution). Maintain variety so the same proof (e.g. Egroma) is not reused back-to-back.
- Cadence target: start 3x/week (matches his prior 1:1:1 plan). Adjust from the measurement loop. The proof-bank is currently thin (5 builds, 2 with open numbers); expanding it is a dependency for sustained cadence.
