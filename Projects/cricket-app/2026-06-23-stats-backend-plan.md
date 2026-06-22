---
type: plan
date: 2026-06-23
project: cricket-app
subproject: stats
status: ready
---

# Stats sub-project - backend plan (TDD, pgTAP)

Backend-first per the standing rules. Migrations manually timestamped
`20260623xxxxxx+`, one object per file; pgTAP test files numbered 61+ (continue
from 60). Reuse the fixture pattern from 32-fold-batting / 34-fold-dismissals
(create_team/add_guest_member/create_match/add_squad_member/start_innings/
record_ball). After each task: red -> green; full suite stays green. Commit per
slice (local only). See `2026-06-23-stats-design.md`.

## Phase 1 - the per-player fold
- **T1 (TDD)**: write `61-compute-innings-cards.test.sql` FIRST (red) - assert
  the cards' batting/bowling/fielding lines equal `compute_innings_state` totals
  on a shared fixture (runs, balls with count_noball_as_ball_faced true+false,
  4s/6s, legal_balls, runs_conceded, maidens, dots, wickets). Cover the
  null-`dismissed_player_id` bowled/caught case -> attributed to the on-strike
  striker; run_out -> attributed to dismissed_player_id; retired_not_out not a
  dismissal. Then add migration `compute_innings_cards(_innings_id)` (lift the
  fold loop). Green.
- **T2**: decide delegation - either refactor `compute_innings_state` to compose
  `compute_innings_cards` (single source) OR keep parallel but run BOTH against
  the 28-37 fold fixtures. Keep the public `compute_innings_state` jsonb shape
  byte-stable (the Flutter viewer depends on it). Re-run 28-37.

## Phase 2 - identity + matches
- **T3 (TDD)**: `65-identity-rollup.test.sql` -> create `v_player_key` +
  `v_player_matches`. Assert a profile playing as different memberships across
  teams rolls up under one key; an unclaimed guest keys by membership id; after
  `approve_guest_claim` the guest's history re-keys to the claimer with no
  backfill/recompute.

## Phase 3 - career + form RPCs
- **T4 (TDD)**: `62/63/64` career batting/bowling/fielding tests -> build
  `player_career_stats(_player_key)` (SECURITY DEFINER, search_path='', STABLE,
  REVOKE ALL + GRANT anon,authenticated) iterating innings via
  `compute_innings_cards`, assembling derived ratios with div-by-zero `-`/null
  guards, HS not-out tie-break, BBI lexicographic, 50s/100s/ducks/4w/5w buckets.
- **T5 (TDD)**: `66-status-filter.test.sql` -> bake the status policy
  (averages: complete; matches-played: complete+abandoned). Setup/live excluded.
- **T6 (TDD)**: `67-recent-form.test.sql` -> `player_recent_form(_player_key,_n)`
  (newest-first, collapse multi-innings per match).
- **T7 (TDD)**: `68-anon-access.test.sql` (mirror 56) -> anon grants resolve
  completed aggregates; no setup-match leak; no broad anon view SELECT.
- **T8 (TDD)**: `69-stats-integration.test.sql` -> full scored match + a
  correction (edit_ball/insert_ball), assert career numbers still equal the
  fold-derived truth (proves read-time recompute survives corrections). Optional
  `player_public_profile` composition wrapper.

## Phase 4 - verify + docs + frontend
- **T9**: `cd backend && supabase db reset && supabase test db` all green; re-seed
  demo data; update backend/README.md scope note; commit.
- **T10 (frontend, AFTER backend green)**: stats repo + providers calling the
  RPCs; public profile stats screen (identity header + batting/bowling cards +
  fielding line + last-5 strip; render `-` for undefined ratios; graceful empty
  state). flutter analyze clean; widget tests BOTH platforms; run on iOS sim +
  live round-trip per the verification protocol; commit.

## Anticipated gotchas (carried from prior sub-projects)
- Explicit `grant execute ... to anon, authenticated`; SECURITY DEFINER fns set
  `search_path=''` and fully-qualify (`public.`).
- Inside pgTAP `$$...$$` use subqueries, not `:vars`.
- Changing an RPC return type needs DROP+CREATE; a `returns table` SRF errors in
  scalar context (wrap in a subquery).
- `db reset` wipes seeded demo data - re-seed after (see CLAUDE.md).
