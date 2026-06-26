---
type: research
date: 2026-06-25
project: cricket-app
subproject: tournaments
status: reference
---

# CricHeroes tournaments - reverse-engineering + gap-matrix vs our v1 design

Deep web research (workflow wf_c999149a-bf2, 6 agents, 78 sourced capabilities;
synthesis below done by hand after the workflow's map/critic steps hit a
transient API error). Sources were largely CricHeroes' own blog/help/Medium +
live tournament pages + app-store listings (2024-2026). Note: cricheroes.com is
Cloudflare-403 to automated fetch, so many claims rest on search-result
summaries of first-party pages cross-checked across sources - exact UI labels
are medium-confidence; the rules/feature SET is high-confidence.

## What CricHeroes' tournament feature actually is
Create-tournament wizard (name/logo, ground, city, **category**, **ball type**
tennis/leather/tape, dates, organizer) -> add teams (create inline / search
existing / **invite link** / **Tournament PIN** self-add) -> **Rounds + Groups/
Pools** -> **Smart Auto-Schedule Generator** (also single + bulk/Excel) ->
public tournament page with sub-tabs: **Points Table (ICC, with NRR)**,
**Leaderboards** (Top Batsman/Bowler/Fielder/**MVP**), **Boundary Tracker**
(most 4s/6s), **Overall Stats**, Schedule (upcoming/past/live), Teams, Sponsors,
News. A tournament match is just a normal **ball-by-ball scored match** (same
engine; live correction; wagon/Manhattan/worm) that auto-feeds the table +
leaderboards. Monetization is PRO subscription + Live Streaming + Power Promote
+ sponsor branding (org itself is free). Annual data-driven awards program.

### Rules we can lock against CricHeroes (confirmed, high-confidence)
- **NRR** = (runs scored / overs faced) - (runs conceded / overs bowled), summed
  over the tournament; **all-out team counts its FULL over quota** in the
  denominator. This is EXACTLY our design's rule.
- **Points**: win 2, tie/no-result 1, loss 0. Matches our design.
- **Tiebreak order**: Points -> NRR -> head-to-head. CricHeroes documents nothing
  beyond head-to-head (so our deterministic final fallback is fine).
- **Player of the Match** is auto, from an **MVP points** algorithm (10 runs = 1
  pt; positional par-score batting weights + SR bonus; format-scaled runs/wicket
  for bowling + multi-wicket/maiden bonuses; ~20% fielder share on assists).

## Gap-matrix vs our approved v1 design

### COVERED (our v1 already at CricHeroes-parity)
- Tournament create (name/venue/city/dates/overs); organizer-run; public page (anon).
- Groups + round-robin + **ICC points table + NRR (same all-out rule)** + tiebreak Points->NRR->H2H.
- Group -> knockout (we do semis+final; CH uses generic rounds+groups - we're a clean subset).
- **Tournament match = a normal scored match** -> inherits scoring, live view, corrections, wagon, per-player stats. (CH does exactly this.)
- Organizer adds teams + assigns groups (we deliberately chose this over self-registration).

### ADD to v1 (high value, LOW cost - we already have the engines)
1. **Tournament leaderboards** - Top run-scorers / wicket-takers / catches + a
   **boundary tracker** (most 4s/6s). We already have `compute_innings_cards` +
   the stats fold; a `tournament_leaderboard(tournament_id)` RPC aggregates the
   tournament's completed matches. This is the single biggest CricHeroes
   tournament surface we'd otherwise miss. **STRONGLY recommend.**
2. **Per-fixture schedule metadata + views** - `scheduled_at` + venue per fixture
   (matches already has the columns) and an upcoming/past/live split on the
   tournament page. Low cost, expected.
3. **Ball type / category** on the tournament (matches already has `ball_type`).
   A default carried to each fixture. Trivial.
4. **Player of the Match per tournament match** - a SIMPLE impact score
   (e.g. runs + 20*wickets + 10*dismissals, winning-side tiebreak), surfaced on
   the match + a tournament "MVP" leaderboard. NOT the full CricHeroes MVP
   algorithm (deferred) - a cheap, recognizable analog. **Recommend (simple).**

### DEFER / OUT OF SCOPE for v1 (note in spec)
- Smart NRR Calculator (what-do-we-need-to-qualify what-if tool) - nice, later.
- Team self-registration via invite link / Tournament PIN (we chose organizer-adds; our team-invite token mechanism could power it later).
- Bulk/Excel schedule upload; auto round-robin "generator" polish (our circle-method generator is enough).
- Byes / non-power-of-2 knockout seeding (our groups+semis+final avoids it).
- Full MVP rating algorithm; annual awards; city/state/national + women's leaderboards.
- Officials directory (umpires/commentators/referees) - we have scorer transfer.
- **Monetization**: PRO subscription, Live Streaming (CH Live Stream app, multi-cam, pricing), Power Promote, sponsor management, banner/poster maker, certificates. All large + credential/payment-bound.
- Non-limited-overs formats (Test/Pair/Hundred/Box) - our engine is limited-overs.
- Entry-fee payment processing - CricHeroes itself does NOT do pass-through entry fees.

## Net
Our v1 already matches the CricHeroes tournament **spine** (create -> groups ->
round-robin -> ICC points table w/ NRR [identical all-out rule] -> semis/final ->
public page -> live scoring on the shared engine). The one high-value thing we'd
miss is **tournament leaderboards + a simple POTM/MVP**, and we already own the
stats engine to build them cheaply - so fold those into the spec. Everything else
CricHeroes has is a deliberate scope choice (self-registration) or genuinely
out-of-scope platform/monetization (streaming, PRO, sponsors, annual awards).
