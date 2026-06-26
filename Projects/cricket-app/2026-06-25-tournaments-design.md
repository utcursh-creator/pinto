---
type: design
date: 2026-06-25
project: cricket-app
subproject: tournaments
status: spec
---

# Tournaments sub-project - design

Group-stage + knockout tournaments, organizer-run, reusing the existing
event-sourced scoring engine + per-player stats. Validated against CricHeroes'
tournament functionality (see `2026-06-25-cricheroes-tournaments-research.md`):
our v1 matches the CricHeroes spine and uses the identical NRR/points/tiebreak
rules; the only CricHeroes surface we deliberately add is tournament
leaderboards + a simple Player-of-the-Match.

## Shape (locked via brainstorming)
Groups (round-robin) -> top `qualifiers_per_group` per group qualify ->
semifinals -> final. v1 supports the canonical 4-qualifier bracket
(`group_count * qualifiers_per_group = 4`, e.g. 2 groups x 2). Organizer adds
teams + assigns groups (no self-registration in v1).

## Key principle: a tournament match IS a normal match
A tournament fixture is an ordinary `matches` row linked by a join table. It
therefore flows through the existing setup wizard, scoring console, live viewer,
corrections, wagon wheel, and feeds player career stats with ZERO new scoring
code. The scoring engine (sub-project #2) stays generic and decoupled.

## Data model (new)
Enums: `tournament_status` (setup, group_stage, playoffs, complete);
`tournament_stage` (group, semifinal, final).

- **`tournaments`**: id, name, organizer_id -> profiles, overs_limit,
  balls_per_over (default 6), ball_type (reuse existing enum, nullable),
  group_count, qualifiers_per_group, status (default setup), champion_team_id ->
  teams (nullable), city, venue, starts_on, ends_on, created_at.
- **`tournament_teams`**: (tournament_id -> tournaments on delete cascade,
  team_id -> teams, group_label text). PK (tournament_id, team_id).
- **`tournament_matches`** (join): match_id PK -> matches on delete cascade,
  tournament_id -> tournaments on delete cascade, stage (tournament_stage),
  group_label (null for playoffs), bracket_slot text (`SF1`/`SF2`/`F`, null for
  group). Index on tournament_id.

Per-fixture schedule + venue need no new columns: `matches` already has
`scheduled_at`, `venue`, `city` (set at fixture creation; drives upcoming/past/
live split). Ball type carries from the tournament default onto each fixture's
`matches.ball_type`.

## RPCs (organizer-gated mutations are SECURITY DEFINER; reads anon-granted)
- `create_tournament(name, overs, group_count, qualifiers_per_group, balls_per_over?, ball_type?, city?, venue?, starts_on?, ends_on?) -> uuid`. Caller becomes organizer.
- `add_tournament_team(tournament_id, team_id, group_label)` - organizer only, status=setup. Guard: team not already in another group of the same tournament.
- `generate_group_fixtures(tournament_id)` - organizer only, status setup -> group_stage. For each group, round-robin via the circle method: create a `matches` row per pairing (team_a, team_b, overs, balls_per_over, ball_type, scorer_id = organizer, status setup) + a `tournament_matches` link (stage group, group_label). Idempotent (refuse if fixtures already exist).
- `tournament_standings(tournament_id) -> jsonb` [SECURITY DEFINER, anon]: per group, one row per team with Played/Won/Lost/Tied/NoResult/Points/NRR, sorted Points -> NRR -> head-to-head -> deterministic (team name). Re-folds completed group matches via `compute_innings_state` (the single source of truth, correct after any score correction).
- `generate_playoffs(tournament_id)` - organizer only; require every group match complete; v1 requires the 2-groups x 2-qualifiers shape. Seed semis cross-group (A1 v B2, B1 v A2) -> matches + links (stage semifinal, bracket_slot SF1/SF2); status playoffs.
- `advance_playoffs(tournament_id)` - organizer only; when both semis complete, create the final (SF1 winner v SF2 winner, bracket_slot F); when the final completes, set champion_team_id + status complete.
- `tournament_leaderboard(tournament_id) -> jsonb` [SECURITY DEFINER, anon]: aggregates the tournament's COMPLETE matches via `compute_innings_cards`, ranking players for: most runs, most wickets, most catches/dismissals, and a boundary tracker (most fours, most sixes). Keyed by team_members.id (each tournament player is one membership), with names.
- `match_potm(match_id) -> jsonb` [SECURITY DEFINER, anon]: a SIMPLE Player-of-the-Match for a completed match - impact = runs + 20*wickets + 10*(catches+run_outs+stumpings), winning-side tiebreak (the winner's best impact wins ties), computed from both innings' cards. Not the full CricHeroes MVP algorithm.
- `tournament_overview(tournament_id) -> jsonb` [SECURITY DEFINER, anon]: one-call composition of tournament meta, teams+groups, standings, fixtures (with stage/result/schedule), the bracket, leaderboard, and champion - for the UI.

## Standings + NRR (the hard part) - locked rules (confirmed = CricHeroes)
Per completed group match, from its two innings (`compute_innings_state` gives
batting_team_id, runs, legal_balls, wickets_remaining):
- A team's **overs faced** = legal_balls/6, UNLESS it was all out
  (`wickets_remaining = 0`) -> the **full over quota** (overs_limit). ICC rule.
- runs_for/overs_for accumulate for the batting team; the same runs+overs become
  the opponent's runs_against/overs_against (the overs it bowled).
- **NRR** = runs_for/overs_for - runs_against/overs_against (aggregate, then
  subtract; never average per-match NRRs).
- **Points** from `matches.result`: win 2, loss 0, tie 1 each, no_result/
  abandoned 1 each.
- **Tiebreak**: Points -> NRR -> head-to-head (winner of the tied teams' group
  match) -> team name (deterministic). CricHeroes documents nothing past H2H.

## RLS / access
`tournaments`, `tournament_teams`, `tournament_matches` are public-readable
(login-free viewing, like live matches); writes only via the organizer-gated
SECURITY DEFINER RPCs. The standings/leaderboard/potm/overview reads are
SECURITY DEFINER granted to anon + authenticated.

## pgTAP plan (continue numbering from 73 -> 74+)
- 74 schema + create_tournament + add_tournament_team + RLS (organizer-only writes; public read).
- 75 generate_group_fixtures (round-robin count = C(n,2) per group; idempotent; status flip).
- 76 tournament_standings: points (win/tie/NR), NRR with all-out full-quota rule, ordering, head-to-head tiebreak.
- 77 generate_playoffs (seeding A1vB2/B1vA2; requires all group matches complete; rejects non-4-qualifier shape).
- 78 advance_playoffs (final from semi winners; champion + complete).
- 79 tournament_leaderboard (runs/wickets/catches/4s/6s across the tournament) + match_potm (impact + winning-side tiebreak).
- 80 integration: a full tournament (2 groups x 3 teams) scored end to end via the real RPCs -> standings, playoffs, champion, leaderboard all correct; plus anon-access (reads resolve for anon; no organizer write as a non-organizer).

## Decomposition (backend-first, TDD; frontend gets its own plan after green)
1. Schema + enums + create/add-team + RLS.
2. Group fixtures (round-robin generator).
3. Standings + NRR + tiebreakers (heaviest).
4. Playoffs seeding + advance + champion.
5. Leaderboard + simple POTM.
6. Overview composition + README + `db reset && test db` + re-seed.

Frontend (separate plan): tournaments list + create; organizer manage (add
teams -> groups, generate fixtures, generate/advance playoffs); public
tournament page (standings tables, fixtures upcoming/past/live, bracket,
leaderboard, champion) wired into the Matches tab; login-free + shareable.

## Out of scope (v1)
Self-registration via invite link / Tournament PIN; the Smart NRR what-if
calculator; bulk/Excel scheduling; byes / non-power-of-2 knockout seeding;
the full CricHeroes MVP rating algorithm; annual / city-state-national / women's
awards + leaderboards; officials directory (umpires/commentators/referees);
all monetization (PRO, live streaming, Power Promote, sponsors, banner maker,
certificates); non-limited-overs formats (Test/Pair/Hundred/Box); entry-fee
payment processing (CricHeroes itself does not do pass-through fees).
