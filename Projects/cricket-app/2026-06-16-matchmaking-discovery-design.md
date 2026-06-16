---
type: spec
date: 2026-06-16
project: cricket-app
sub-project: matchmaking-discovery
layer: backend
status: draft
tags: [cricket-app, spec, matchmaking, geo, postgis, realtime, dm, supabase]
---

# Cricket App - Sub-project #3: Matchmaking & Discovery (Design Spec)

## Project context

This is the app's CORE differentiator and the original wedge: connect players and teams to play cricket nearby. Three "looking-for" needs, surfaced as a GEO-TARGETED FEED of posts, with public replies and private 1:1 chat to actually connect:
- a player who needs a team,
- a team that needs 2-3 players,
- a team that wants an opponent (-> a match).

It is the "find a game" half that feeds the already-built "play & record" half (Identity & Teams + Scoring Core). Loop: discover nearby -> connect -> form the match (reuse existing team invite/claim) -> play -> score (done) -> profile.

- **Stack:** Supabase (Postgres + PostGIS + Realtime + Auth). Flutter client later.
- **Builder:** solo + AI; controller-TDD + pgTAP, same discipline as the prior two backends.
- **Reuses:** `profiles`, `teams`, `team_members`, `is_team_admin`; the broadcast-from-DB realtime idiom; the SECURITY DEFINER helper pattern; the explicit-grants-to-`authenticated` local rule.

### Decisions locked (brainstorming)
1. **All three post modes:** player_seeking_team / team_seeking_players / team_seeking_opponent.
2. **Connect = BOTH** public post replies AND private 1:1 direct messages (realtime). Group/team chat deferred.
3. **Location model:** a settable **home base** per user (persisted), plus a **"near me now"** live-GPS toggle on the feed. Same discovery query, different anchor point passed by the client.
4. **Posts carry their own location** (the game's ground/area) and **expire**. Joining a team after connecting reuses the existing invite/claim flow (no new mechanism).

### Verified + corrected (PostGIS/realtime verification workflow)
The geo + private-realtime architecture was verified against current Supabase/PostGIS docs. It is sound; the spec below bakes in the corrections, the most important being a **location-privacy fix** and several PostGIS precision rules.

---

## Architecture

- **PostGIS** does proximity. Locations are `geography(Point, 4326)` (metre-accurate). Discovery is a `SECURITY DEFINER` RPC that filters with `ST_DWithin` (index-assisted), orders by the `<->` KNN operator against a **constant anchor point passed as a parameter**, and returns **distance, never raw coordinates**.
- **Discovery is post-centric.** The only geo objects exposed to other users are `looking_for_posts` (which the author deliberately advertised). A user's own home location is a **private anchor** used only to run their feed; it is never returned to anyone else. This closes most of the trilateration surface by construction.
- **Private DM** reuses the broadcast-from-DB realtime idiom, but with a **participant-scoped** `realtime.messages` receive policy (the public match feed was open; DMs must be strictly private).

---

## Data model

### Extension (hand-written, early, standalone migration)
```sql
create extension if not exists postgis with schema "extensions";
```
Do NOT let `supabase db diff` generate this (migra emits duplicate `CREATE TYPE geometry_dump`/`valid_detail` that break the next `db reset`). pgTAP guard: `select has_extension('postgis')`.

### Enums
- `lf_mode`: player_seeking_team | team_seeking_players | team_seeking_opponent
- `lf_status`: open | filled | cancelled | expired
- `skill_level`: beginner | intermediate | advanced (nullable on posts)

### Location storage (PRIVACY-CRITICAL: separate tables, NOT a column on profiles)
Putting `home_geog` on `profiles` would inherit `profiles_select_authenticated USING(true)` and leak everyone's raw coordinates. So location lives in its own tables with **no client-readable SELECT** - only the owner may upsert their own row; reads happen only inside `SECURITY DEFINER` RPCs.

`profile_locations`
| column | type | notes |
|---|---|---|
| profile_id | uuid PK -> profiles(id) cascade | |
| geog | extensions.geography(Point,4326) not null | the user's home base |
| place_label | text | display ("Andheri, Mumbai"), free text |
| updated_at | timestamptz default now() | |

`team_locations` - same shape keyed by team_id (a team's home base; used to prefill a team's post location). Owner = team admin.

RLS: `enable row level security`; grant select/insert/update to `authenticated`; policy allows a row only where `profile_id = (select auth.uid())` (teams: `is_team_admin(team_id)`). **No `USING(true)` select** - other users cannot read locations at all. The discovery RPC (definer) is the only path that reads them, and it returns distance, not the point.

### `looking_for_posts`
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| author_id | uuid -> profiles(id) | |
| team_id | uuid -> teams(id) null | set for team_seeking_players / team_seeking_opponent |
| mode | lf_mode not null | |
| title / description | text | free text |
| geog | extensions.geography(Point,4326) not null | the game/availability location (intentionally discoverable) |
| place_label | text | human location |
| match_at | timestamptz null | when the game is |
| overs | int null | format |
| skill | skill_level null | |
| slots_needed | int null | for team_seeking_players |
| status | lf_status not null default 'open' | |
| expires_at | timestamptz null | auto-considered expired past this |
| created_at | timestamptz default now() | |

Indexes: `using gist (geog)` (partial `where status = 'open'` for the hot path); `(author_id)`; `(team_id)`.

### `post_replies`
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| post_id | uuid -> looking_for_posts(id) cascade | |
| author_id | uuid -> profiles(id) | |
| body | text not null | |
| created_at | timestamptz default now() | |

### Direct messages (canonical 1:1)
`dm_threads`: `id uuid pk`, `user_lo uuid not null`, `user_hi uuid not null`, `created_at`, `constraint dm_threads_ordered check (user_lo < user_hi)`, `unique index (user_lo, user_hi)` - the normalized pair key prevents duplicate threads.
`dm_participants`: `thread_id -> dm_threads`, `profile_id -> profiles`, `unique(thread_id, profile_id)` (denormalized membership for fast/recursion-free RLS checks).
`dm_messages`: `id`, `thread_id -> dm_threads cascade`, `sender_id -> profiles`, `body text not null`, `read_at timestamptz null`, `created_at default now()`.

---

## Helpers & RPCs (all SECURITY DEFINER; `set search_path` as noted; granted to `authenticated`)

- `set_my_location(_lat float, _lng float, _label text default null)` - upsert `profile_locations` for `auth.uid()`. Builds the point as `extensions.st_setsrid(extensions.st_makepoint(_lng, _lat), 4326)::extensions.geography` (longitude FIRST). `set_team_location(_team_id, _lat, _lng, _label)` - same, gated by `is_team_admin`.
- `discover_posts(_lat float, _lng float, _radius_m float default 25000, _mode lf_mode default null, _max_overs int default null, _on_or_after timestamptz default null, _skill skill_level default null)` returns a table of safe fields (`post_id, author_id, team_id, mode, title, description, place_label, match_at, overs, skill, slots_needed, approx_m`). `language sql security definer set search_path = ''`. Filters `status='open'` and not expired and `extensions.st_dwithin(geog, anchor, _radius_m)` and the optional filters; orders by `geog operator(extensions.<->) anchor` (anchor = the parameter point, kept constant so the GiST index is used); `approx_m = round(extensions.st_distance(geog, anchor)/100)*100`. Returns NO geog/lat/lng. `_lat/_lng` is the client's home base OR live "near me" point.
- `create_looking_for_post(...)`, `cancel_post(_post_id)`, `mark_post_filled(_post_id)` - author/team-admin gated.
- `is_thread_participant(_thread_id uuid) returns boolean` - `security definer set search_path = public stable`, `exists(select 1 from dm_participants where thread_id=_thread_id and profile_id=auth.uid())`. The recursion-breaker, mirroring `is_team_admin`.
- `get_or_create_dm_thread(_other uuid) returns uuid` - compute `least/greatest(auth.uid(), _other)`, `insert ... on conflict (user_lo,user_hi) do nothing`, insert both `dm_participants`, then return the thread id. Race-safe + idempotent.
- `send_dm(_thread_id uuid, _body text)` OR direct insert gated by RLS (with check `is_thread_participant(thread_id) and sender_id = auth.uid()`). Spec uses direct insert + RLS.

**PostGIS-in-definer rule:** every function with `set search_path = ''` MUST fully-qualify PostGIS calls (`extensions.st_dwithin`, `extensions.st_distance`, `extensions.st_setsrid`, `extensions.st_makepoint`, `::extensions.geography`, `operator(extensions.<->)`). pgTAP test files may call them unqualified (extensions is on the session path).

---

## RLS (the airtight parts)

- `profile_locations` / `team_locations`: owner-only (no `USING(true)`); definer RPCs read them. This is the privacy fix - location is never client-selectable.
- `looking_for_posts`: SELECT to `authenticated` (`USING(true)` - posts are meant to be found; note discovery is via the RPC, but a direct select is acceptable since posts are public objects). INSERT/UPDATE: author, or team admin when `team_id` set.
- `post_replies`: **explicit** - enable RLS; SELECT `USING(true)` to `authenticated`; INSERT `with check author_id = auth.uid()`; author/post-owner may delete. (An RLS-enabled table with no policy denies all; never leave implicit.)
- `dm_threads` SELECT `using is_thread_participant(id)`; `dm_participants` SELECT `using profile_id = auth.uid() or is_thread_participant(thread_id)`; `dm_messages` SELECT `using is_thread_participant(thread_id)`, INSERT `with check is_thread_participant(thread_id) and sender_id = auth.uid()`.
- Every new table gets explicit `grant select, insert, update[, delete] ... to authenticated` (local reset does not auto-grant).

## Realtime (private DM)
AFTER INSERT trigger on `dm_messages` -> `broadcast_dm_message()` (`security definer set search_path = ''`, `coalesce(NEW,OLD)`, exception-swallowing) calling `realtime.broadcast_changes('dm:'||thread_id, ...)`. Receive policy on `realtime.messages`:
```sql
create policy "dm_broadcast_receive" on realtime.messages for select to authenticated
using (realtime.messages.extension = 'broadcast'
       and realtime.topic() like 'dm:%'
       and public.is_thread_participant((split_part(realtime.topic(), ':', 2))::uuid));
```
**`to authenticated` only (NOT anon)**, and the `::uuid` cast is mandatory. Client MUST use `channel('dm:'+id, { config: { private: true } })` after `realtime.setAuth(token)` - a non-private channel never consults this policy and would let any authed user subscribe to any DM. No INSERT policy on `realtime.messages` (the definer trigger writes; clients only receive).

## Privacy summary
1. Home/team locations live in dedicated tables with **no client SELECT**; only definer RPCs read them.
2. Discovery returns **coarsened distance** (`round(.../100)*100`) and place labels, **never coordinates**.
3. Discovery is **post-centric** - we never expose player-to-player distance, so trilateration of a person's home has no surface.
4. DM channels are **private** (participant-scoped receive policy + `private:true`).

---

## Testing (pgTAP, TDD)
- `has_extension('postgis')`; location tables exist with correct geog type; GiST indexes present.
- **Geo proximity + lng/lat-swap guard:** insert fixtures ~2km and ~50km from an anchor; assert the near one IS returned by `discover_posts(...,10000)`, the far one is NOT, AND the near `approx_m` is BETWEEN ~1900 and ~2100 (a lng/lat swap blows the magnitude up by hundreds of km - the boolean in/out check alone would not catch a swap, the magnitude check does). Loose tolerance for spheroid math.
- **Privacy boundary:** an authenticated non-owner CANNOT select another user's `profile_locations` row; `discover_posts` output has no lat/lng/geog column.
- **Filters + lifecycle:** mode/overs/date/skill filters; expired and cancelled posts excluded.
- **DM gating:** a non-participant cannot select/insert into a thread's messages (42501 / 0 rows); participants can; `get_or_create_dm_thread` is idempotent (same pair -> same thread id, one row).
- **DM realtime contract:** `has_function broadcast_dm_message` + `has_trigger dm_messages_broadcast` (broadcast itself asserted via the integration flow, like the scoring broadcast test).
- **Integration:** a player posts (player_seeking_team) near point X; a captain at point Y (~3km) discovers it; opens a DM via `get_or_create_dm_thread`; both exchange messages; captain invites the player to the team (reusing the existing invite flow); post marked filled.

## Out of scope (v1)
- Push notifications ("new post near you") and geo-filtered realtime feed PUSH (the feed is pull/refresh in v1).
- Group/team chat (1:1 DM only).
- Browsing players/teams directly by location (discovery is post-centric; a "players near me" directory is a later feature and would need its own privacy model).
- Reputation/blocking/reporting/moderation beyond basic auth gating (a trust-and-safety pass is a later sub-project; note `realtime` policy caches per connection, so a future "block" only takes effect on reconnect).
- `use_spheroid=false` perf tuning (keep default true; revisit at scale with loose test tolerances).

## Decomposition (for writing-plans, 4 phases, each TDD)
1. **Geo foundation** - postgis extension; `profile_locations` + `team_locations` (private RLS); `set_my_location` / `set_team_location`; GiST; privacy + geo pgTAP.
2. **Looking-for posts + discovery** - enums; `looking_for_posts` + GiST + RLS; create/cancel/fill RPCs; `discover_posts` RPC; proximity/filter/expiry pgTAP.
3. **Post replies** - table + explicit RLS + pgTAP.
4. **Direct messages** - threads/participants/messages; `is_thread_participant`; `get_or_create_dm_thread`; send + RLS; broadcast trigger + private `realtime.messages` policy; gating + contract pgTAP; the end-to-end integration test.

## Open items (non-blocking)
- Default discovery radius (spec uses 25 km) - tune later; it is a parameter.
- Whether a post may optionally expose a coarse map pin (author opted in) vs distance-only - v1 is distance + place label; revisit when the map UI is designed.
- The geo migration for the EXISTING Identity backend: this sub-project ADDS location tables; it does not modify `profiles`/`teams` columns (free-text `city` stays). No rewrite of sub-project #1.
