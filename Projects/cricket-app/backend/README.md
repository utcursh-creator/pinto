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

## Matchmaking & Discovery (sub-project #3)

The app's core differentiator: a geo-targeted feed that connects players and teams nearby. Additive to Identity/Scoring (free-text `city` stays; this adds location tables and PostGIS).

### Geo + privacy
- PostGIS (`extensions` schema). Locations are `geography(Point,4326)`; distances/radii are METRES.
- Home location lives in PRIVATE tables (`profile_locations`, `team_locations`) with NO client SELECT (owner-only). They are read ONLY inside SECURITY DEFINER RPCs. Set via `set_my_location(lat,lng)` / `set_team_location(...)`.
- Discovery returns COARSENED distance (rounded to 100m), never coordinates. It is post-centric, so player-to-player coordinates are never exposed.

### Looking-for posts + feed
- `looking_for_posts`: `mode` (player_seeking_team / team_seeking_players / team_seeking_opponent), author/team, the game's own `geog` + place label, match_at/overs/skill/slots_needed, status, expires_at.
- `discover_posts(lat, lng, radius_m, mode?, max_overs?, on_or_after?, skill?)` -> open, unexpired posts within radius (GiST + `ST_DWithin`), ordered by the `<->` KNN operator against the anchor point, returning each post + `approx_m`.
- Lifecycle RPCs: `create_looking_for_post`, `cancel_post`, `mark_post_filled`. Joining a team after connecting reuses the existing invite/claim flow.

### Connect
- `post_replies`: public comment thread per post (RLS: read all authenticated; write own).
- Private 1:1 DM: `dm_threads` (canonical `user_lo<user_hi` pair) + `dm_participants` + `dm_messages`. `get_or_create_dm_thread(other)` is idempotent. RLS is participant-gated via the `is_thread_participant` SECURITY DEFINER helper.
- Realtime: an AFTER INSERT trigger on `dm_messages` calls `realtime.broadcast_changes('dm:<thread>', ...)`. The `realtime.messages` receive policy is PARTICIPANT-SCOPED and `authenticated`-only; clients MUST subscribe with `{ config: { private: true } }` after `realtime.setAuth(token)`.

### PostGIS rules (for future edits)
- SECURITY DEFINER functions use `set search_path = ''` and therefore fully-qualify every PostGIS call (`extensions.st_dwithin`, `extensions.st_distance`, `extensions.st_setsrid`, `extensions.st_makepoint`, `::extensions.geography`, `operator(extensions.<->)`). Point builder is lng-FIRST: `st_setsrid(st_makepoint(LNG, LAT), 4326)`.
- The PostGIS-enabling migration is hand-written (never `db diff`, which emits duplicate `CREATE TYPE` that breaks reset).

### Out of scope (v1)
Push notifications, geo-filtered realtime feed PUSH (feed is pull/refresh), group chat, a players-near-me directory, moderation/blocking beyond auth gating.
