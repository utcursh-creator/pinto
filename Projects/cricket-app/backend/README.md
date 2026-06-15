# Cricket App backend (Identity and Teams)

Supabase (Postgres + RLS) backend. Authentication is Google/Apple social login, configured in the Supabase dashboard, not in code (no SMS, no phone OTP in v1).

## Run locally
1. Install [Supabase CLI](https://supabase.com/docs/guides/local-development) (`brew install supabase/tap/supabase`) and a Docker runtime (Docker Desktop or OrbStack).
2. From `Projects/cricket-app/backend/`: `supabase start`
3. Apply schema + seed (loads pgTAP + test helpers): `supabase db reset`
4. Run the test suite: `supabase test db`

## Layout
- `supabase/migrations/` schema, RLS, and RPCs, one object per file, applied in filename (timestamp) order.
- `supabase/tests/` pgTAP tests, one file per migration, run alphabetically.
- `supabase/seed.sql` LOCAL-ONLY: installs pgTAP and the vendored basejump test helpers. Runs on `db reset`, never on `db push` to production.

## Data model
- `profiles` one row per auth user (id references auth.users); phone is optional and unverified.
- `teams` name, city, logo, created_by.
- `team_members` membership; either `profile_id` (real user) or `guest_name` (guest), enforced by a check constraint. A profile appears at most once per team (partial unique index). Users can belong to many teams.
- `team_invites` shareable-link or phone invites.
- `guest_claim_requests` a user's request to claim a guest membership.

## Key RPCs (all SECURITY DEFINER; granted to `authenticated`)
- `create_team(name, city, logo_url) -> team_id` creates the team and the caller's captain membership.
- `add_guest_member(team_id, guest_name) -> membership_id` admin-only.
- `accept_invite(invite_token) -> membership_id` idempotent, concurrency-safe.
- `request_guest_claim(membership_id) -> request_id`
- `approve_guest_claim(membership_id, claimer_id) -> void` admin-only; transfers the guest membership to the claimer.

## Authorization
RLS is enabled on every table and enforced in Postgres. Cross-table checks (is the caller a team admin?) live in the `is_team_member` / `is_team_admin` SECURITY DEFINER helpers to avoid policy recursion. The `authenticated` role is granted base DML on each table; RLS gates which rows.

## Deploy (later)
- `supabase link` to a hosted project, then `supabase db push` to apply migrations (seed.sql is not pushed).
- Configure Google + Apple providers and redirect URLs in the dashboard Auth settings.

## Scoring Core (sub-project #2)

Event-sourced ball-by-ball scoring. A ball is a fact in `deliveries` (ordered by a monotonic per-innings `seq`); the entire scorecard is a single pure fold, `compute_innings_state(innings_id) -> jsonb`, which is the ONLY home for cricket rules. Corrections re-fold; there are no hand-maintained totals.

### Tables
- `matches` (teams, scorer, overs, balls_per_over, toss, venue/city/ball_type/pitch_type, rules jsonb, result jsonb), `match_squad` (playing XI: batting order, captain, keeper), `innings` (opening pair, target, revised_overs), `deliveries` (decomposed extras, generated `is_legal`, wagon_x/y/zone, fold-stamped striker/non_striker).
- `team_members.bats` added for wagon-wheel orientation.

### The fold output (compute_innings_state)
runs/wickets/legal_balls/over, extras breakdown, batting card (+ did_not_bat), bowling card (overs/maidens/runs/wickets/economy/dots/wides/no-balls), fall_of_wickets, partnerships (+ current), per_over (Manhattan), worm, striker/non_striker/free_hit_active, crr/rrr/runs_required/balls_remaining/wickets_remaining, innings_status, result, orphaned_deliveries.

### Scoring RPCs (SECURITY DEFINER, scorer-gated, advisory-locked per innings)
- `create_match`, `add_squad_member`, `start_innings`
- `record_ball` (folds to stamp strike; rejects illegal dismissals on no-ball/free-hit/wide; enforces no consecutive overs unless `rules.allow_consecutive_overs`)
- `undo_last_ball`, `edit_ball`, `delete_ball`, `insert_ball` (full correction; the fold re-derives the cascade)
- `set_match_result` (no_result / abandoned / manual winner)

### Live broadcast
Supabase Realtime Broadcast-from-database: an AFTER INSERT/UPDATE/DELETE trigger on `deliveries` calls `realtime.broadcast_changes('match:<id>', ...)`. Live scores are public (login-free), so the `realtime.messages` receive policy is open to `authenticated, anon` on `match:%` topics. Clients re-fold on every event.

### Rule scope (v1)
Standard limited-overs, full fidelity (all extras, all 11 dismissals, free-hit chaining, engine-owned strike). Out of scope: DLS/VJD calculation, powerplays, super over, Test/multi-day, custom gully variants (the schema supports >2 innings and rule toggles for later). Cross-match stats (MVP, milestones, career, H2H, NRR) belong to a Stats sub-project; tournaments to a Tournaments sub-project.
