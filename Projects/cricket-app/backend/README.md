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
Supabase Realtime Broadcast-from-database: an AFTER INSERT/UPDATE/DELETE trigger on `deliveries` calls `realtime.broadcast_changes('match:<id>', ...)`. Live scores are public (login-free), so the `realtime.messages` receive policy is open to `authenticated, anon` on `match:%` topics. Clients re-fold on every event. The Flutter client must `signInAnonymously()` before subscribing so the WebSocket gets a token even for anon viewers (see sub-project #4).

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

### Team invites (registered players)
`create_team_invite(team_id)` (SECURITY DEFINER, admin-gated) mints an unguessable server-generated token and inserts a pending `team_invites` row; the invitee redeems it via the existing `accept_invite(token)` to join as a player. This is the registered-player path (guests use add-guest + guest-claim). pgTAP test 73.

### Home-location read-back (self/team only)
`my_home_location()` and `team_home_location(team_id)` (SECURITY DEFINER, authenticated) return a saved point decoded to lat/lng (the geog column is PostGIS binary). The location tables stay non-broadly-readable (privacy); these expose only the caller's OWN home base and a team ground to its members. The client uses `my_home_location` to default the discover anchor instead of a hardcoded city. pgTAP test 72.

### Out of scope (v1)
Push notifications, geo-filtered realtime feed PUSH (feed is pull/refresh), group chat, a players-near-me directory, moderation/blocking beyond auth gating.

## Frontend-prep additive changes (sub-project #4)

Closes the gaps an audit of the wireframes found before the Flutter build. All additive; 244 pgTAP tests pass.

- **Post flair (required)**: `lf_flair` enum (`loser_pays` / `practice_match` / `corporate_match`), NOT NULL on `looking_for_posts`. `create_looking_for_post` takes a required `_flair` (after `_mode`); `discover_posts` takes an optional `_flair` filter and returns `flair` per row.
- **Scorer reassignment**: `transfer_scorer(match_id, new_scorer_id)` - advisory-locked, status-gated (setup/live/innings_break), caller = current scorer or admin of either team, new scorer = member of either team, eligibility validated even on a same-scorer no-op.
- **Login-free viewing**: anon SELECT policies on `matches / innings / deliveries / match_squad / team_members / teams`, gated by `matches.status in ('live','innings_break','complete','abandoned')`. Registered names via `public_profile_minimal(profile_id)` (display_name / photo_url / batting_style only); guest names via the gated `team_members` policy. Client must `signInAnonymously()` for the realtime WebSocket.
- **Wagon-wheel hint**: `record_ball` returns `table(delivery_id, wagon_applicable)`. `wagon_applicable` is true only for a directional bat shot (no wide/bye/leg-bye, any no-ball off the bat, dismissal in caught/run_out), so both clients share one server-owned prompt rule.

See `../2026-06-17-frontend-prep-backend-design.md` and `-plan.md`.

## Post attachments (photos + link)

- `looking_for_posts.image_urls text[] not null default '{}'` + `link_url text`.
- Public Storage bucket `post-images` (5 MiB; jpeg/png/webp) created in a migration. RLS on `storage.objects`: authenticated INSERT/DELETE only into the uploader's own `<uid>/` folder (`(storage.foldername(name))[1] = auth.uid()::text`); public SELECT (feed images load via CDN).
- `create_looking_for_post` takes optional `_image_urls text[]` + `_link_url text` (appended last); `discover_posts` returns `image_urls` + `link_url`.

## Player stats (sub-project #5)

Career + recent-form stats derived by RE-FOLDING each innings - no new tables, no flat aggregation (a flat `deliveries` view mis-attributes bowled/caught/lbw/stumped, which `record_ball` leaves with a null `dismissed_player_id`, and drifts after corrections). The fold stays the single source of truth.

- **`compute_innings_cards(innings_id) -> jsonb`** (SECURITY INVOKER, STABLE): a per-player generalization of `compute_innings_state` - identical strike rotation, `count_noball_as_ball_faced` rule, bowler-credited wicket set, maiden over-window and dismissal attribution, but emits `{batting:[{member_id,runs,balls,fours,sixes,dismissed,how_out}], bowling:[{member_id,legal_balls,runs_conceded,wickets,maidens,dots,wides,no_balls}], fielding:[{member_id,catches,run_outs,stumpings}]}`. The two folds are kept in lockstep by divergence-guard assertions in test 61 (cards totals must equal `compute_innings_state` on a shared fixture). `compute_innings_state`'s public jsonb shape is unchanged.
- **`v_player_key` / `v_player_matches`** (`security_invoker` views, granted to `authenticated` only): identity rollup `player_key = COALESCE(team_members.profile_id, id)` (a claimed user rolls up across teams; an unclaimed guest keys by membership id; `approve_guest_claim` re-keys history at read time with zero backfill) + matches-played from `match_squad` over `status in ('complete','abandoned')`.
- **`player_career_stats(player_key) -> jsonb`**, **`player_recent_form(player_key, n) -> jsonb`**, **`player_public_profile(profile_id) -> jsonb`** (SECURITY DEFINER, `search_path=''`, granted `anon, authenticated`): batting (Mat/Inns/NO/Runs/HS not-out-aware/Avg/SR/4s/6s/50s/100s/Ducks), bowling (Overs/Balls/Runs/Wkts/BBI/Avg/Econ/SR/Maidens/4w/5w), fielding (Catches/Run-outs/Stumpings), last-N form strip, and a one-round-trip composition wrapper. Undefined ratios return `null` (client renders `-`).
- **Status policy**: averages/aggregates fold COMPLETE matches only; matches-played counts complete + abandoned; setup/live never leak to anon. `retired_out` counts as a dismissal; 4w bucket = exactly 4. Anon reaches stats only through the definer RPCs (the identity views are not anon-selectable).
- Total: **343 pgTAP tests** (61-69, 71 added; 70 = strike re-stamp).

See `../2026-06-23-stats-design.md` and `-backend-plan.md`.

---
**For the full development index, current state, run/test/seed commands, the verification protocol, and the slice roadmap, see `../CLAUDE.md` (the canonical entry point).**
