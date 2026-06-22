---
type: design
date: 2026-06-23
project: cricket-app
subproject: stats
status: spec
---

# Stats sub-project - design (career batting/bowling/fielding + recent form)

Player-profile enrichment derived from the existing event-sourced scoring data.
Backend-first, TDD with pgTAP. No new tables/columns - the data is already in
`deliveries`/`innings`/`matches`/`match_squad`/`team_members`. Verified design
(stat formulas + Supabase approach) via workflow wf_9e8d6fea-035.

## Key decision: re-fold per innings, do NOT flat-aggregate deliveries
A flat SQL view over delivery columns is UNSAFE here:
1. `record_ball` does not set `dismissed_player_id` for bowled/caught/lbw/
   stumped/hit_wicket - the fold attributes those to the on-strike striker. A
   flat `dismissed_player_id = player` undercounts most outs.
2. The stored `deliveries.striker_id` snapshot is rotation-correct only on the
   live `record_ball` append path; `edit_ball` leaves it stale and `insert_ball`
   stamps the opening pair. After any correction a flat view silently disagrees
   with the scorecard, while `compute_innings_state` stays correct because it
   re-derives strike each call.
3. Maidens, HS, BBI, 50s/100s, 4w/5w are inherently per-innings, not flat sums.

So: `compute_innings_state` is the single source of truth. Stats re-fold each
innings (cheap at amateur scale - a few hundred balls). Plain VIEWs are used
only for the trivially-flat parts (the player grouping key + matches-played from
the squad). Materialized views are deferred (the corrections RPC mutates past
balls; refresh-on-correction plumbing is not justified now).

## DB objects (all SECURITY DEFINER RPCs set search_path='' + fully qualify)
- `compute_innings_cards(_innings_id uuid) -> jsonb` [SECURITY INVOKER, STABLE]:
  a multi-player generalization of `compute_innings_state` - same fold loop
  (strike rotation, count_noball_as_ball_faced, bowler-credited wicket set,
  maiden over-window) but emits per-player lines:
  `{batting:[{member_id,runs,balls,fours,sixes,dismissed,how_out}],
    bowling:[{member_id,legal_balls,runs_conceded,wickets,maidens,dots,wides,no_balls}],
    fielding:[{member_id,catches,run_outs,stumpings}]}`.
  The two folds must not diverge: either `compute_innings_state` delegates to
  this, or both are covered by the SAME fold fixtures (tests 28-37).
- `v_player_key` VIEW: `member_id, player_key = COALESCE(profile_id, id), profile_id`
  from `team_members` (valid via the profile-xor-guest CHECK).
- `v_player_matches` VIEW: matches played per player_key from `match_squad`
  (definitive who-played) over status in ('complete','abandoned').
- `player_career_stats(_player_key uuid) -> jsonb` [SECURITY DEFINER, anon+authenticated]:
  resolves the key to all member_ids sharing it, finds every innings in
  COMPLETE matches those members appeared in, folds each via
  `compute_innings_cards`, sums per innings, computes derived ratios + the
  per-innings buckets. Status filter baked in (anon cannot reach setup/live
  data) - mirrors `public_profile_minimal`.
- `player_recent_form(_player_key uuid, _n int default 5) -> jsonb`: last N
  completed matches, one batting + bowling line per match (collapse multi-innings).
- `player_public_profile(_profile_id uuid) -> jsonb` (optional thin wrapper):
  composes public_profile_minimal + career + recent_form for one round-trip.

## Stat set (v1) + formulas (verified)
Batting: Mat, Inns, NO, Runs, HS (not-out aware, render `72*`), Avg, SR, 4s, 6s,
50s, 100s, Ducks. Bowling: Mat, Overs, Balls, Runs, Wkts, BBI, Avg, Econ, SR,
Maidens. Fielding: Catches, Run-outs, Stumpings. Plus a last-5 form strip.
- `times_out` = innings where the resolved out-batter = player AND wicket_type
  not in (retired_not_out, retired_out); resolved out-batter = run_out/obstructing
  -> dismissed_player_id, else the fold's on-strike striker.
- `not_outs = innings_batted - times_out`
- `batting_avg = runs / NULLIF(times_out,0)` -> render `-` when 0 (UNDEFINED).
- `balls_faced`: striker=player, extra_wides=0, and (no_ball_penalty=0 OR
  count_noball_as_ball_faced) - NOT `is_legal` (a no-ball is faced).
- `batting_sr = 100 * runs / NULLIF(balls_faced,0)` -> `-` when 0.
- HS from per-innings max (not SUM), not-out tie-break. 50s = [50,99], 100s = >=100
  (a 100 is not also a 50). Ducks = runs=0 AND dismissed. 4s/6s from off-bat boundaries.
- `wickets` credited only for bowled/caught/lbw/stumped/hit_wicket (not run_out).
- `runs_conceded` = runs_off_bat + wides + no_ball_penalty (byes/leg-byes/penalty excluded).
- `econ = runs_conceded / (legal_balls/6)` using TRUE overs (10.2 ov = 10.333), `-` when 0.
- `bowling_avg = runs_conceded / NULLIF(wickets,0)`; `bowling_sr = legal_balls / NULLIF(wickets,0)`; `-` when 0.
- BBI = per-innings max on (wickets, -runs), format `W/R`. Maidens from the fold over-window.
- 4w = exactly 4 wickets in an innings; 5w = >=5. Fielding by fielder_id + wicket_type.
- Mat = distinct match_id from match_squad; innings_batted = innings where player faced >=1 ball OR was the resolved out-batter.

## Identity
Aggregate by `player_key = COALESCE(team_members.profile_id, id)`. Claimed users
roll up across their per-team memberships; unclaimed guests key by membership id
(no standalone public page until claimed). `approve_guest_claim` rewrites
`profile_id` in place on the same row, and all delivery actor columns reference
`team_members(id)` - so a claim re-keys the guest's entire history to the
claimer at read time with zero backfill.

## Login-free + privacy
Career/recent-form RPCs are SECURITY DEFINER, granted anon+authenticated, with
the completed-status filter baked in; return aggregate numbers + anon-safe
identity only (no phone/city/email). Never grant anon a broad SELECT on a career
view. Mirrors the existing anon-viewing privacy stance.

## Open product decisions (defaults chosen; confirm)
1. Status set: averages count `complete` only; matches-played counts
   `complete`+`abandoned`. [default]
2. 4-wicket-haul bucket = exactly 4 (ESPNcricinfo). [default] vs "4+".
3. `retired_out` counts as a dismissal against the average. [default: yes]
4. Run-outs shown as a fielding line (app extension, not an ICC-standard career column). [default: show]

## Out of scope (v1)
H2H, MVP/ratings (no per-player award data), leaderboards/rankings, NRR
(Tournaments), tournament-scoped stats, milestones/awards/badges, position/
opposition/venue/phase splits, materialized rollups, standalone pages for
unclaimed guests.

## Related backend note
The stored `deliveries.striker_id` drifting after `edit_ball`/`insert_ball` is
not a stats bug (the fold re-derives), but it is a latent footgun for any future
flat consumer. Tracked separately; stats deliberately never trust the stored
stamp.

See `2026-06-23-stats-backend-plan.md` for the TDD task plan.
