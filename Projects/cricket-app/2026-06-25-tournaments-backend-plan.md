---
type: plan
date: 2026-06-25
project: cricket-app
subproject: tournaments
status: ready
---

# Tournaments sub-project - backend plan (TDD, pgTAP)

Backend-first per the standing rules. Reuses the scoring engine end to end (a
tournament fixture is a normal `matches` row + a `tournament_matches` link).
Migrations manually timestamped `20260625xxxxxx+`, one object per file; pgTAP
test files numbered 74+ (continue from 73). After each task: red -> green; full
suite stays green. `db reset` wipes seeded demo data - re-seed after (CLAUDE.md).
Controller-TDD (subagent dispatch billing-blocked). See `2026-06-25-tournaments-design.md`.

## Established gotchas to apply pre-emptively
- Every table needs explicit `grant ... to authenticated` (local reset does not auto-grant); add anon SELECT where public.
- SECURITY DEFINER fns: `set search_path = public` (or `''` + fully-qualify); REVOKE ALL then GRANT to the intended roles.
- Inside pgTAP `$$...$$` use subqueries, not `:vars`.
- Changing an RPC return type needs DROP+CREATE; a `returns table` SRF in scalar context must be wrapped in a subquery.
- `compute_innings_state(innings)` gives batting_team_id, runs, legal_balls, wickets_remaining (0 = all out), result. `compute_innings_cards(innings)` gives per-member batting/bowling/fielding. `set_match_result` writes matches.result + status complete/abandoned.

## Phase 1 - schema + create + RLS
- **T1 (TDD)**: `74-tournaments-schema.test.sql` (red). Assert: create_tournament returns an id + sets organizer = caller + status 'setup'; add_tournament_team inserts a (team, group_label) row; a NON-organizer cannot add a team (throws P0001); public/anon can SELECT a tournament row; a non-organizer cannot UPDATE it.
- Implement migrations: `..120000_tournament_enums.sql` (tournament_status, tournament_stage); `..120100_tournaments.sql` (table + RLS: select to anon+authenticated using(true); insert/update/delete gated to organizer_id = auth.uid()); `..120200_tournament_teams.sql` + `..120300_tournament_matches.sql` (tables + RLS, public read, write via definer RPCs only - no direct client write policy needed, but grant select); `..120400_rpc_create_tournament.sql`; `..120500_rpc_add_tournament_team.sql` (SECURITY DEFINER, is-organizer guard via a helper `is_tournament_organizer(_t)` ; status must be 'setup'). Green.

## Phase 2 - group fixtures
- **T2 (TDD)**: `75-group-fixtures.test.sql` (red). Fixture: tournament, 2 groups, group A = 3 teams, group B = 3 teams. Call generate_group_fixtures. Assert: 3 matches per group (C(3,2)=3) -> 6 `tournament_matches` rows stage='group' with correct group_label; each linked `matches` row has status 'setup', the tournament's overs/ball_type, scorer = organizer; tournament status flips to 'group_stage'; a second call is rejected (idempotent guard) ; a non-organizer is rejected.
- Implement `..120600_rpc_generate_group_fixtures.sql` (SECURITY DEFINER): organizer + status='setup' guard; for each group_label, round-robin via the circle method over its teams; per pairing insert a `matches` row (team_a, team_b, owner+scorer=organizer, overs_limit, balls_per_over, ball_type, city, status default 'setup') + a `tournament_matches` link; flip status 'group_stage'; raise if any `tournament_matches` already exist for the tournament. Green.

## Phase 3 - standings + NRR (heaviest)
- **T3 (TDD)**: `76-standings.test.sql` (red). Build a small completed group (3 teams, scripted innings via insert deliveries + set_match_result) with KNOWN runs/overs/wickets so NRR is hand-computable, including one all-out innings (assert it uses the FULL over quota, not actual overs). Assert per-team Played/Won/Lost/Tied/NoResult/Points; NRR value; ordering points->NRR; a head-to-head tiebreak case (two teams equal points+NRR -> the H2H winner ranks higher).
- Implement `..120700_rpc_tournament_standings.sql` (SECURITY DEFINER, anon+authenticated, STABLE): resolve the tournament's group-stage `matches` with status 'complete'; for each, read both innings via compute_innings_state; per innings compute overs_faced = wickets_remaining=0 ? overs_limit : legal_balls/6.0; accumulate runs_for/overs_for (batting team) + runs_against/overs_against (bowling team); points from matches.result (win 2 / tie 1 / no_result|abandoned 1 / loss 0); per group emit rows sorted points desc, NRR desc, then head-to-head (compare the tied teams' direct match winner), then team name. Return jsonb `{groups:[{group_label, rows:[{team_id,name,played,won,lost,tied,no_result,points,nrr}]}]}`. Green.

## Phase 4 - playoffs + champion
- **T4 (TDD)**: `77-playoffs.test.sql` (red). 2 groups x 2 teams, all group matches complete. generate_playoffs: assert it rejects while any group match is not complete; on success creates 2 semifinal `tournament_matches` (bracket_slot SF1/SF2) seeded A1 v B2 and B1 v A2 from standings; status -> 'playoffs'; rejects a non-4-qualifier shape (e.g. group_count<>2).
- **T5 (TDD)**: `78-advance.test.sql` (red). With both semis complete, advance_playoffs creates the final (SF1 winner v SF2 winner, bracket_slot F); after the final completes, advance_playoffs sets champion_team_id + status 'complete'. Assert each.
- Implement `..120800_rpc_generate_playoffs.sql` + `..120900_rpc_advance_playoffs.sql` (SECURITY DEFINER, organizer-gated). Seeding reads tournament_standings; winner of a played match from matches.result.winner_team_id. Green.

## Phase 5 - leaderboard + POTM
- **T6 (TDD)**: `79-leaderboard-potm.test.sql` (red). On a small completed tournament: tournament_leaderboard returns top run-scorers / wicket-takers / catches / most-4s / most-6s with correct totals + a known #1; match_potm(match_id) returns the right player by impact = runs + 20*wickets + 10*(catches+run_outs+stumpings) with the winning-side tiebreak.
- Implement `..121000_rpc_tournament_leaderboard.sql` + `..121100_rpc_match_potm.sql` (SECURITY DEFINER, anon+authenticated). Both fold the tournament's COMPLETE matches via compute_innings_cards, key by team_members.id, join names. Green.

## Phase 6 - overview + integration + docs
- **T7 (TDD)**: `80-tournament-overview.test.sql` + integration. tournament_overview(id) composes meta+teams/groups+standings+fixtures(stage/result/schedule)+bracket+leaderboard+champion in one jsonb. Full integration: build a 2-group x 3-team tournament, score every group match + the playoffs via the real RPCs, assert champion + final standings + leaderboard are correct, AND an anon caller can read standings/leaderboard/overview while a non-organizer cannot mutate.
- **T8**: `cd backend && supabase db reset && supabase test db` all green; re-seed demo data; add a "Tournaments (sub-project #6)" section to backend/README.md; commit.

## Phase 7 - frontend (SEPARATE plan, after backend green)
Tournaments list + create wizard; organizer manage (add teams -> groups, generate fixtures, generate/advance playoffs); public tournament page (standings tables, fixtures upcoming/past/live, bracket, leaderboard, champion) wired into the Matches tab; login-free + shareable; verification protocol (analyze + both-platform widget tests + iOS sim run + live round-trip + commit).

## Anticipated gotchas (carried)
- create_match is a SECURITY DEFINER RPC that sets owner/scorer = auth.uid(); generate_group_fixtures runs as the organizer (definer with auth.uid() = organizer) so inserting matches directly (not via create_match) is simpler + lets us set status/teams without the toss flow - insert matches rows directly inside the definer fn with scorer_id = organizer.
- Standings NRR division by zero: a team with 0 overs faced/bowled (no completed match) -> guard with NULLIF -> NRR null (render '-').
- matches.result jsonb shape: `{result_type, winner_team_id, ...}` (win_by_wickets/win_by_runs/tie/no_result/abandoned). Read result_type + winner_team_id.
- A tournament match's two innings: standings must handle a match with both innings present; a match with <2 innings (incomplete) is excluded by the status='complete' filter.
