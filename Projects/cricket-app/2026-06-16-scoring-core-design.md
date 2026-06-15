---
type: spec
date: 2026-06-16
project: cricket-app
sub-project: scoring-core
layer: backend
status: draft
tags: [cricket-app, spec, scoring, event-sourced, supabase, postgres, realtime]
---

# Cricket App - Sub-project #2: Scoring Core (Design Spec)

## Project context

CricHeroes-style cricket app. Sub-project #1 (Identity and Teams backend) is built: `profiles`, `teams`, `team_members` (real-or-guest membership via XOR), `team_invites`, `guest_claim_requests`, Google/Apple auth, RLS. This sub-project is the **scoring backend**: the ball-by-ball engine, live broadcast, full correction, and the per-match setup it needs. The Flutter scoring UI (including the wagon-wheel tap surface) is a later sub-project.

- **Stack (locked):** Flutter (later) | Supabase (Postgres + Realtime + Auth + Storage) | online-required scoring.
- **Builder:** solo + AI assistance; controller-TDD + pgTAP, same as Identity and Teams.
- **Builds on:** `teams`, `team_members`, `profiles`. Player references point at `team_members.id` (NOT `profiles.id`) so guest players with no account can bat/bowl/field.

### Decisions locked during brainstorming
1. **Fidelity:** standard limited-overs, FULL fidelity (configurable overs, complete extras, all dismissals, strike rotation, free hit, innings-end logic). No DLS calculation, powerplays, or custom gully variants in v1.
2. **Corrections:** full correction - undo/edit/delete/insert any past ball mid-match; the scorecard recomputes.
3. **Scorer model:** single authoritative scorer (`scorer_id`, a team admin/owner); everyone else read-only live; reassignable.
4. **Strike:** the ENGINE owns strike (the fold derives the striker every ball; the scorer sets only the opening pair and the incoming batter on a wicket).
5. **Config:** strict ICC limited-overs defaults in a `matches.rules` jsonb, structured so recreational toggles can be added later without migration.

### Decisions locked after the CricHeroes gap analysis
6. **Wagon wheel:** capture per-ball shot location in v1 (nullable columns); it cannot be back-filled by a downstream stats project.
7. **Real-world completeness:** support rain-shortened matches via `innings.revised_overs` (manual reduced overs, NO DLS math) and a fuller `result_type` taxonomy including `no_result` and a manually-set winner.
8. **Innings model:** design for >2 innings now (uncapped `innings_number`, nullable/derived `target`); v1 still only ships limited-overs, but super-over and any future multi-innings format avoid a painful migration.
9. **Match metadata:** include descriptive setup columns (venue, city, scheduled_at, ball_type, pitch_type) and a per-match playing-XI squad (batting order, captain, keeper) in v1.

Grounded in MCC 2017 Code (3rd ed. 2022) + ICC ODI/T20I playing conditions; rule details verified by an adversarial research workflow, then mapped against CricHeroes for parity (see "Gap-closure log").

---

## Architecture: event-sourced, single fold

A ball is a fact; the scorecard is a function of the facts.

- Each delivery is a row in `deliveries`, ordered by a monotonic per-innings `seq bigint`.
- One PL/pgSQL function, `compute_innings_state(innings_id)`, performs a **single left-fold** over `deliveries ORDER BY seq` and returns the ENTIRE innings state (totals, per-batter/per-bowler cards, extras, partnerships, charts, current striker/bowler/free-hit, FoW, live rates, result). It is the **single home for all cricket rules**.
- **No hand-maintained running totals anywhere.** Correctness on edits comes from re-folding: editing ball 3 from a single to a wide un-rotates strike, shifts the over boundary, can change which bowler was legal, and can move the innings/chase end for every later ball. Only a re-fold captures that cascade. An innings is bounded (~120-300 deliveries) so a full fold is sub-millisecond. The `innings_summary` write-through cache is DEFERRED (only if a cross-match leaderboard later needs it, and even then a full recompute via the same function, never a delta).

---

## Data model

### Enums
- `match_status`: setup | live | innings_break | complete | abandoned
- `innings_status`: in_progress | completed
- `toss_decision`: bat | bowl
- `ball_type`: leather | tennis | tape | other
- `pitch_type`: turf | matting | cement | astroturf | other
- `noball_secondary_kind`: off_bat | bye | leg_bye  (how the runs beyond a no-ball penalty are classified)
- `bats_hand`: RHB | LHB  (added to `team_members` for wagon-wheel orientation)
- `wicket_type`: bowled | caught | lbw | run_out | stumped | hit_wicket | retired_out | retired_not_out | obstructing | timed_out | hit_ball_twice
- `result_type`: win_by_runs | win_by_wickets | tie | tie_superover | win_dls | win_vjd | no_result | abandoned | conceded | forfeit | walkover | awarded  (v1 IMPLEMENTS win_by_runs, win_by_wickets, tie, no_result, abandoned + manual winner; the rest are reserved enum values the Tournaments sub-project will own)
- `margin_method`: normal | DLS | VJD  (for recording how a result was reached; v1 only sets `normal`/`no_result`)

### `team_members` (sub-project #1) - additive change
Add `bats bats_hand null` (nullable; seed from `profiles.batting_style` for real users; settable for guests). Needed so the wagon wheel can mirror zones for left-handers. One `ALTER TABLE` migration; does not disturb existing Identity behavior.

### `matches`
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| team_a_id / team_b_id | uuid FK -> teams | |
| owner_id | uuid FK -> profiles | creator |
| scorer_id | uuid FK -> profiles default owner | single authoritative scorer; reassignable |
| overs_limit | int | overs per innings (per side) |
| balls_per_over | int default 6 | configurable (forward-compat for 5/10-ball sets) |
| rules | jsonb default '{}' | `free_hit_enabled`, `no_ball_penalty`, `count_noball_as_ball_faced`, `squad_size`, `last_man_stands`, `timed_out_secs`, `allow_consecutive_overs` |
| toss_winner_id | uuid FK -> teams null | |
| toss_decision | toss_decision null | "won the toss and elected to {bat\|bowl}"; seeds innings batting/bowling assignment |
| venue / city | text null | descriptive |
| scheduled_at | timestamptz null | |
| ball_type | ball_type null | enables leather-vs-tennis stat segmentation downstream |
| pitch_type | pitch_type null | |
| status | match_status default 'setup' | |
| result | jsonb null | structured result, set on completion (see below) |
| created_at | timestamptz | |

### `match_squad` (NEW)
The per-match playing XI for each team. Underpins batting order, did-not-bat, and opener/incoming pickers.
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| match_id | uuid FK -> matches (cascade) | |
| team_id | uuid FK -> teams | |
| team_member_id | uuid FK -> team_members | real or guest player |
| batting_order | int null | |
| is_captain / is_wicket_keeper / is_substitute | bool default false | |
| UNIQUE(match_id, team_member_id) | | |

### `innings`
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| match_id | uuid FK -> matches (cascade) | |
| innings_number | int | NOT capped at 2 (designed for >2: super-over/future multi-innings) |
| batting_team_id / bowling_team_id | uuid FK -> teams | |
| opening_striker_id / opening_non_striker_id | uuid FK -> team_members | the opening pair; engine derives strike onward |
| overs_limit | int null | per-innings override (else inherit match) |
| revised_overs | int null | rain-shortened reduced overs (manual/agreed; NO DLS math). Fold uses COALESCE(revised_overs, overs_limit, matches.overs_limit) |
| target | int null | set for a chasing innings; nullable/derived rather than hardcoded innings1+1 |
| status | innings_status default 'in_progress' | |
| UNIQUE(match_id, innings_number) | | |

### `deliveries` (the event log)
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| innings_id | uuid FK -> innings (cascade) | |
| seq | bigint | monotonic per innings; COALESCE(MAX(seq),0)+1 under advisory lock; gap-tolerant |
| bowler_id | uuid FK -> team_members | scorer-entered |
| runs_off_bat | int default 0 | credited to the striker |
| extra_wides | int default 0 | total wide runs (1 penalty + runs run), all scored as wides |
| extra_no_ball_penalty | int default 0 | the no-ball penalty only (config 1 or 2) |
| extra_byes | int default 0 | byes (legal ball, or off a no-ball) |
| extra_leg_byes | int default 0 | leg-byes (legal ball, or off a no-ball) |
| extra_penalty | int default 0 | separately-awarded 5-run penalties (NOT charged to bowler) |
| noball_secondary_kind | noball_secondary_kind null | classifies the non-penalty runs on a no-ball |
| is_legal | bool GENERATED ALWAYS AS (extra_wides = 0 AND extra_no_ball_penalty = 0) STORED | re-bowled iff false; cannot drift |
| wicket_type | wicket_type null | |
| dismissed_player_id | uuid FK -> team_members null | REQUIRED for run_out/obstructing |
| incoming_batter_id | uuid FK -> team_members null | who comes in; the fold derives which end |
| fielder_id | uuid FK -> team_members null | caught/run_out/stumped attribution |
| crossed | bool null | batters crossed at the instant (run_out/obstruction strike) |
| prevented_catch | bool null | obstruction sub-case |
| is_overthrow | bool default false | |
| overthrow_crossed | bool null | additive overthrow strike parity |
| wagon_x / wagon_y | real null | shot location tap (raw, for re-render) |
| wagon_zone | smallint null | resolved 1..8 sector, normalized to the batter's perspective at capture |
| commentary_text | text null | optional manual commentary override |
| striker_id / non_striker_id | uuid FK -> team_members | FOLD-STAMPED by the RPC (engine owns strike); re-stamped on edit; self-describing for display/broadcast |
| created_at / updated_at | timestamptz | |
| UNIQUE(innings_id, seq) | | |
| CHECK NOT (extra_wides > 0 AND extra_no_ball_penalty > 0) | | a ball is never both a wide and a no-ball |

**Derived, never stored authoritative:** over_number, ball_in_over, free_hit_active, totals, partnerships, who-faces-next, result (the `striker_id/non_striker_id` columns are a fold-stamped convenience copy, not free-entered).

**Indexes:** `deliveries(innings_id, seq)` unique; `innings(match_id, innings_number)` unique; `match_squad(match_id, team_member_id)` unique; `matches(scorer_id)`; `matches(owner_id)`.

---

## The rule engine (inside `compute_innings_state`)

### Delivery outcome matrix (verified)
Per ball the fold applies team runs / batsman credit / ball-faced / bowler charge / strike / free-hit, reading the decomposed extra columns directly:

- **Dot (legal):** team +0; batsman +0, +1 ball faced; legal; maiden-eligible; strike unchanged; free hit consumed.
- **Runs off bat N (1/2/3):** team/batsman/bowler +N; legal; strike swaps iff N odd; free hit consumed.
- **Boundary 4/6 off bat:** +4/+6 to team/batsman (fours/sixes++)/bowler; legal; strike unchanged; free hit consumed.
- **Wide (`extra_wides`):** team + extra_wides; batsman +0, NOT a ball faced; NOT legal (re-bowled); bowler + extra_wides (breaks maiden); strike swaps iff the runs-run portion is odd; **free hit carries over**.
- **No-ball (`extra_no_ball_penalty` + secondary):** team + penalty + secondary; secondary is `runs_off_bat` (credited to batsman) OR `extra_byes`/`extra_leg_byes` (team only) per `noball_secondary_kind`; NOT legal; bowler charged the penalty + off-bat runs but **NOT byes/leg-byes run off a no-ball**; +1 ball faced iff `count_noball_as_ball_faced`; strike swaps iff the run portion is odd; **free hit set TRUE** for the next legal ball.
- **Bye/leg-bye N (`extra_byes`/`extra_leg_byes`):** team +N; batsman +0, +1 ball faced; legal; **bowler NOT charged** (maiden-eligible); strike swaps iff N odd; free hit consumed.
- **Penalty 5 (`extra_penalty`):** team +5; batsman +0; bowler NOT charged; does not change the legal-ball count; strike unchanged.
- **Overthrow:** ADDITIVE (boundary 4 + completed runs + run-in-progress if `overthrow_crossed`); credited to batsman only if the contact was off the bat; strike set by the running portion's parity, not the boundary.
- **Free hit that is itself a wide/no-ball:** scores per its own row AND the free-hit flag REMAINS TRUE (chains indefinitely; loop the boolean, never a counter).

### Dismissals (verified)
- **Bowler-credited:** bowled, caught, lbw, stumped, hit_wicket. **Not credited:** run_out, obstructing, retired_out, timed_out, hit_ball_twice.
- **No-ball / free-hit allowed set = EXACTLY {run_out, obstructing, hit_ball_twice}.** Stumped is NOT allowed (it is a run_out). Enforced as a write-RPC guard off the folded prior-ball free-hit state.
- **Wide allowed set = {hit_wicket, obstructing, run_out, stumped}.**
- **Caught:** completed bat-runs do not score (penalties stand); not-out batter ALWAYS returns to the original end; per the Oct-2022 ICC change the incoming batter takes the striker's end regardless of crossing.
- **Run out / obstructing:** either batter (store `dismissed_player_id`); completed runs + penalties stand; next-ball strike uses `crossed`.
- **Timed out:** incoming batter, no delivery tie-in, window from `timed_out_secs`. **Retired-out** consumes a wicket; **retired-not-out** does not and the batter stays available to return.

### Stat derivations (verified)
- **Batsman balls faced** = on-strike deliveries where not a wide AND (not a no-ball OR `count_noball_as_ball_faced`).
- **Batsman runs** = sum(runs_off_bat); fours/sixes only off the bat. SR = runs/balls*100 (NULL if 0).
- **Bowler runs conceded** = off-bat runs + extra_wides + extra_no_ball_penalty + off-bat runs on a no-ball; EXCLUDES extra_byes, extra_leg_byes (incl. off a no-ball) and extra_penalty. Economy = conceded/(legal_balls/6).
- **Maiden over** = 6 legal balls, 0 runs charged to the bowler; byes/leg-byes-only over IS a maiden; any wide or no-ball breaks it.
- **Over display X.Y** from an integer `legal_balls` counter (X = /6, Y = %6); never string arithmetic.
- **Bowler-change guard:** at over rollover the next bowler != previous over's bowler, UNLESS `rules.allow_consecutive_overs` (forward-compat for The Hundred / recreational).
- **Innings end (priority):** (1) chasing innings and runs > target-1 (i.e. >= target) -> won; (2) all out via availability model (squad-1, or squad if `last_man_stands`); (3) allotted legal balls bowled, using `COALESCE(revised_overs, overs_limit) * balls_per_over`. Deliveries after the true end are FLAGGED as orphaned, not scored.
- **Result:** target = chased_innings_total + 1; equal at end -> TIE; else win by runs (defending) or by wickets (chasing). A non-play result (`no_result`, `abandoned`, manual winner) can be set without a fold-derived margin.

---

## Fold output contract (`compute_innings_state` returns)

The live scorecard and the standard finished scorecard cannot render unless these are committed as returned fields (all derivable in the one fold):

- **Totals:** runs, wickets, legal_balls, over display X.Y, extras breakdown {byes, leg_byes, wides, no_balls, penalty}.
- **Batting card** (per batter): runs, balls, fours, sixes, SR, dismissal descriptor; plus **did_not_bat[]** = squad minus batters who faced/were dismissed (needs `match_squad`).
- **Bowling card** (per bowler): overs X.Y, maidens, runs, wickets, economy, **dot_balls, wides_bowled, no_balls_bowled** (clean from decomposed extras).
- **Fall of wickets[]:** {wicket_number, score_at_fall, over.ball, dismissed_player_id}.
- **Partnerships[]:** {wicket_number, batter_a_id, batter_b_id, runs, balls, a_runs, a_balls, b_runs, b_balls, start_score, end_score} (current partnership too).
- **Live rates:** crr; rrr, runs_required, balls_remaining, wickets_remaining (chasing innings); current_over_balls[] (this-over strip); projected_score.
- **Charts:** per_over[] {over_number, runs_in_over, wickets_in_over} (Manhattan); worm[] {over_index or seq, cumulative_runs, cumulative_wickets}.
- **State:** current striker / non_striker / bowler, free_hit_active, innings_status.
- **Structured result** (on completion, persisted to `matches.result`): {winner_team_id null, result_type, margin_runs null, margin_wickets null, balls_remaining null, wickets_remaining null, margin_method, note null}.
- **orphaned_deliveries[]:** any deliveries after the true innings-end.
- **Integrity invariant the fold asserts:** sum(batsman runs) + all extras == team total.

---

## Corrections, RPCs, broadcast, RLS

### Mutation RPCs (SECURITY DEFINER; each takes `pg_advisory_xact_lock(hashtextextended(innings_id::text,0))`)
- `record_ball(innings_id, <outcome incl. decomposed extras + optional wagon_x/y/zone>)` - folds to determine strike/free-hit/dismissal-legality (rejects illegal dismissals + the consecutive-over violation unless toggled), allocates seq, stamps striker/non_striker, inserts.
- `undo_last_ball(innings_id)` - DELETE max(seq).
- `edit_ball(delivery_id, <fields>)` / `delete_ball(delivery_id)` - UPDATE/DELETE; re-fold (gaps tolerated).
- `insert_ball(innings_id, after_seq, <fields>)` - renumber seq > after_seq inside the lock, then insert.
- `set_match_result(match_id, result_type, winner_team_id null, note null)` - scorer/organiser action for non-play results (no_result, abandoned, manual winner); allows completion with < 2 full innings.

### Live broadcast
Supabase Realtime **Broadcast-from-database** (not Postgres Changes). `AFTER INSERT/UPDATE/DELETE` trigger on `deliveries` calls a SECURITY DEFINER function (`SET search_path = ''`) resolving `match_id` via `innings.match_id` and `realtime.broadcast_changes('match:'||match_id, ...)`. One private channel per match. Exception-safe inside the trigger (never blocks ball entry). Clients treat every event as a re-fold signal; a local optimistic delta is allowed only for a plain tail INSERT, never a correction.

### RLS
RLS on `matches`, `innings`, `deliveries`, `match_squad` (defense-in-depth; writes go through definer RPCs). Public SELECT for live viewing (optionally gate to `status <> 'setup'`). Writes on `deliveries`/`innings`/`match_squad` allowed only for the match `scorer_id`, via an `is_match_scorer(match_id)` SECURITY DEFINER helper (mirrors `is_team_admin`; `auth.uid()` wrapped in a subselect; base DML granted to `authenticated`, matching the Identity tables which need explicit local grants). Realtime private-channel receive needs a `realtime.messages` SELECT policy scoped to `topic LIKE 'match:%'` (`to anon` too if logged-out viewing is wanted). Single-scorer correctness boundary = `scorer_id` + the advisory lock, never an `is_locked` flag.

### State machines
- **match_status:** setup -> live -> innings_break -> live -> complete; abandoned reachable from any state; `set_match_result` can move setup/live -> complete (no_result/abandoned).
- **innings_status:** in_progress -> completed (target exceeded | all out | overs bowled).

---

## Testing (pgTAP, TDD)

The fold is pure and deterministic. Tests assert `compute_innings_state` output against hand-built delivery sequences:
- **Rule-matrix:** wide carries free hit; no-ball sets free hit; byes off a no-ball charge only the penalty to the bowler; penalty-5 not charged; overthrow additive 4+2=6; maiden broken by a wide but not by leg-byes; strike swap on odd runs and at over end; boundary returns batters to ends.
- **Decomposed extras:** the extras breakdown and bowler-conceded read directly from columns; the CHECK (not both wide and no-ball) holds; `is_legal` generated correctly.
- **Dismissal guards:** stumped/bowled/caught/lbw rejected on no-ball and free hit (only run_out/obstructing/hit_ball_twice accepted); caught returns not-out batter to original end + incoming takes strike; run_out uses `crossed`.
- **Correction-cascade (core risk):** edit an early ball (single -> wide) and assert strike, over boundary, bowler legal-ball count, partnerships, and totals all re-derive for every later ball; undo-last; delete-middle (gap tolerated); insert-missed-ball (renumber).
- **Squad / cards:** did_not_bat[] = squad minus batted; batting order from `match_squad`; bowling dots/wides/no-balls.
- **Fold output contract:** crr/rrr/runs_required/balls_remaining/wickets_remaining; partnerships[]; per_over[]; worm[]; current_over_balls[]; structured result with balls/wickets remaining.
- **Revised overs:** an innings with `revised_overs` ends at the reduced count; balls_remaining/RRR honor it.
- **Result taxonomy:** win_by_runs / win_by_wickets / tie; `set_match_result` records no_result and a manual winner (null margin); completion with < 2 innings allowed for abandoned/no_result.
- **Wagon data:** round-trips through record_ball/edit_ball; zone normalization respects `team_members.bats`.
- **RLS:** non-scorer cannot write deliveries (42501); public read; scorer writes via RPC.
- **Integrity invariant:** sum(batsman runs) + extras == team total across the above.

## Explicitly out of scope (v1)
- DLS / VJD **calculation** (a result can be RECORDED as DLS via `result_type`/`margin_method`, but no par-score math). Powerplays, per-bowler over-quota hard enforcement (soft warning toggle later), super over (schema now supports >2 innings, so it is a planned fast-follow, not built in v1).
- Custom gully/box/tennis-ball house rules beyond the jsonb toggles already present (negative/bonus runs, pairs base-score, lbw-disable).
- Test / multi-day / declarations / follow-on (schema no longer hardcodes 2 innings, but the aggregate-result + unlimited-overs logic is a future format effort).
- Pitch map, shot type, ball-tracking. Live video streaming, AI highlights, AI CricInsights.
- Cross-match / career stats, milestones, badges, MVP / Player-of-the-Match, head-to-head, Net Run Rate -> Sub-project #3 (Stats and Rankings); tournament tables/fixtures/officials/admin results (conceded/forfeit/walkover/awarded) -> a Tournaments sub-project; scorecard share-images -> Social. The Scoring Core fold stays innings-scoped but EMITS the per-player aggregates + fielder attribution + result + format these consume.
- `innings_summary` write-through cache (deferred). Flutter scoring UI incl. the wagon-wheel tap surface (later sub-project; the columns are captured now).

## Open items (non-blocking)
- `timed_out_secs` preset (MCC 180s / ODI 120s / T20I 90s) - pick at build; stored in `rules`.
- `no_ball_penalty` default 1 (some leagues 2) - in `rules`.
- Wagon `wagon_field_orientation`: zones are stored normalized to the batter's perspective at capture, so a separate orientation column is not required; revisit if raw x/y re-rendering needs the original field orientation.
- MCC 2026 code (effective 1 Oct 2026) does not alter the strike/over/innings mechanics used here; pin to 2017 Code (3rd ed. 2022) + ICC overlay; treat 2026 as a future config bump.

## Gap-closure log (vs CricHeroes)
A research workflow mapped CricHeroes' full scoring surface against this spec. The engine math was found parity-or-better (and a superset on corrections). Closed in this revision: decomposed extras; wagon-wheel columns + `team_members.bats`; `match_squad` (XI/order/captain/keeper); `toss_decision`; `allow_consecutive_overs` toggle; `revised_overs`; fuller `result_type` + `set_match_result`; >2-innings-ready schema; descriptive match metadata; and the full fold output contract (live rates, partnerships, Manhattan, worm, did-not-bat, bowling dots/wides/no-balls, structured result). Confirmed correctly downstream (MVP, milestones, career stats, H2H, NRR, tournaments, share-images) or out of scope (pitch-map, shot-type, DLS calc, video, Test).
