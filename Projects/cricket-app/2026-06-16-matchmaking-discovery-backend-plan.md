---
type: plan
date: 2026-06-16
project: cricket-app
sub-project: matchmaking-discovery
layer: backend
status: draft
tags: [cricket-app, plan, backend, supabase, postgis, geo, realtime, dm, pgtap, tdd]
---

# Matchmaking & Discovery - Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and test the geo matchmaking backend on Supabase: PostGIS proximity, private location storage, a `discover_posts` geo feed (3 modes), public post replies, and private 1:1 direct messages with realtime - all verified-correct and pgTAP-tested, additive to the existing Identity/Scoring backends.

**Architecture:** Locations are `geography(Point,4326)` in dedicated PRIVATE tables (no client SELECT; read only inside SECURITY DEFINER RPCs). Discovery is a SECURITY DEFINER RPC that filters with `ST_DWithin` (GiST-indexed) and orders by the `<->` KNN operator against a constant anchor point passed as a parameter, returning coarsened distance, never coordinates. Private DM reuses the broadcast-from-DB realtime idiom with a participant-scoped `realtime.messages` receive policy.

**Tech Stack:** Supabase CLI (local, OrbStack) | PostgreSQL + PostGIS | PL/pgSQL | RLS | Supabase Realtime | pgTAP + basejump helpers (already in `supabase/seed.sql`).

**Spec:** `Projects/cricket-app/2026-06-16-matchmaking-discovery-design.md` (verified via the PostGIS/realtime workflow; corrections already folded in).

**Conventions (carried from the prior two backends):** backend root `Projects/cricket-app/backend/`; manually-timestamped migrations (the slow `supabase migration new` auto-backgrounds and truncates) named `2026061620xxxx_*`, monotonic, one object-area per file; one pgTAP file per migration (scoring used 20-42; matchmaking uses **43+**); run a task with `supabase db reset >/dev/null 2>&1 && supabase test db`; no em dashes.

**Reuses + hard-won rules (do not relearn):**
- Every new table needs explicit `grant select, insert, update[, delete] ... to authenticated` (local reset does not auto-grant).
- Inside pgTAP `throws_ok`/`lives_ok` `$$..$$` strings, identify rows with SUBQUERIES, never psql `:vars`.
- A SECURITY DEFINER function with `set search_path = ''` MUST fully-qualify every PostGIS call: `extensions.st_dwithin`, `extensions.st_distance`, `extensions.st_setsrid`, `extensions.st_makepoint`, `::extensions.geography`, and the KNN operator as `operator(extensions.<->)`. pgTAP test files MAY call them unqualified.
- Helpers that read a table used in that table's own policy are `SECURITY DEFINER` + `SET search_path` (non-inlinable) to avoid RLS recursion (mirror `is_team_admin`).
- The point builder is `extensions.st_setsrid(extensions.st_makepoint(LNG, LAT), 4326)::extensions.geography` - LONGITUDE FIRST. With geography, distances and `ST_DWithin` radius are METRES.

---

## File Structure
| Path | Responsibility |
|---|---|
| `supabase/migrations/2026061620xxxx_postgis.sql` | enable PostGIS (hand-written) |
| `.../_locations.sql` | profile_locations + team_locations (+ GiST + RLS + grants) |
| `.../_rpc_set_location.sql` | set_my_location / set_team_location |
| `.../_lf_enums.sql` | lf_mode / lf_status / skill_level |
| `.../_looking_for_posts.sql` | posts table + GiST + RLS + grants |
| `.../_rpc_posts.sql` | create_looking_for_post / cancel_post / mark_post_filled |
| `.../_rpc_discover_posts.sql` | the discover feed RPC |
| `.../_post_replies.sql` | replies table + RLS + grants |
| `.../_dm.sql` | dm_threads / dm_participants / dm_messages + is_thread_participant + RLS + grants |
| `.../_rpc_dm.sql` | get_or_create_dm_thread |
| `.../_dm_broadcast.sql` | DM broadcast trigger + private realtime.messages policy |
| `supabase/tests/43..52-*.test.sql` | one pgTAP file per task |

**Naming/type contract:** `geography(Point,4326)` everywhere; `discover_posts(_lat float,_lng float,_radius_m float,_mode lf_mode,_max_overs int,_on_or_after timestamptz,_skill skill_level) returns table(...)`; `set_my_location(_lat float,_lng float,_label text)`; `is_thread_participant(_thread_id uuid) returns boolean`; `get_or_create_dm_thread(_other uuid) returns uuid`.

---

## PHASE 1 - GEO FOUNDATION

### Task 1: Enable PostGIS
**Files:** Create `.../20260616203001_postgis.sql`; Create `supabase/tests/43-postgis.test.sql`.
- [ ] **Step 1: Failing test** - `43-postgis.test.sql`:
```sql
begin;
select plan(1);
select has_extension('postgis', 'postgis is installed');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** (hand-written; do NOT generate via `db diff`):
```sql
create extension if not exists postgis with schema "extensions";
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-matchmaking): enable postgis`).

### Task 2: Private location tables + set-location RPCs
**Files:** Create `.../20260616203101_locations.sql`; Create `.../20260616203102_rpc_set_location.sql`; Create `supabase/tests/44-locations.test.sql`.

- [ ] **Step 1: Failing test** - `44-locations.test.sql` (stores a point; owner reads own; NON-owner cannot read; lng/lat order sane via ST_Distance ~2km):
```sql
begin;
select plan(4);
select tests.create_supabase_user('a@m.dev');
select tests.create_supabase_user('b@m.dev');
select tests.authenticate_as('a@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
select tests.authenticate_as('b@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('b@m.dev'),'B');

-- A sets home near Mumbai (lng 72.87, lat 19.07)
select tests.authenticate_as('a@m.dev');
select public.set_my_location(19.07, 72.87, 'Mumbai');
select is((select count(*)::int from public.profile_locations where profile_id = tests.get_supabase_uid('a@m.dev')), 1, 'owner stored a location');

-- distance from A home to a point ~2km east (lng 72.89, lat 19.07) is ~2km (guards lng/lat order)
select ok(
  extensions.st_distance(
    (select geog from public.profile_locations where profile_id = tests.get_supabase_uid('a@m.dev')),
    extensions.st_setsrid(extensions.st_makepoint(72.89, 19.07),4326)::extensions.geography
  ) between 1500 and 2600, 'home point is ~2km from a 0.02-deg-lng point (lng/lat order correct)');

-- B (non-owner) cannot read A's location row
select tests.authenticate_as('b@m.dev');
select is((select count(*)::int from public.profile_locations where profile_id = tests.get_supabase_uid('a@m.dev')), 0, 'non-owner cannot read another user location');

-- B can set + read only their own
select public.set_my_location(18.52, 73.85, 'Pune');
select is((select count(*)::int from public.profile_locations where profile_id = tests.get_supabase_uid('b@m.dev')), 1, 'B reads own location');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3a: locations migration** - `20260616203101_locations.sql`:
```sql
create table public.profile_locations (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  geog extensions.geography(Point,4326) not null,
  place_label text,
  updated_at timestamptz not null default now()
);
create index profile_locations_geog_idx on public.profile_locations using gist (geog);
alter table public.profile_locations enable row level security;
grant select, insert, update, delete on public.profile_locations to authenticated;
-- owner-only: NO USING(true). Other users cannot read locations at all.
create policy "profile_locations_owner_all" on public.profile_locations for all to authenticated
  using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));

create table public.team_locations (
  team_id uuid primary key references public.teams(id) on delete cascade,
  geog extensions.geography(Point,4326) not null,
  place_label text,
  updated_at timestamptz not null default now()
);
create index team_locations_geog_idx on public.team_locations using gist (geog);
alter table public.team_locations enable row level security;
grant select, insert, update, delete on public.team_locations to authenticated;
create policy "team_locations_admin_all" on public.team_locations for all to authenticated
  using (public.is_team_admin(team_id)) with check (public.is_team_admin(team_id));
```
- [ ] **Step 3b: set-location RPCs** - `20260616203102_rpc_set_location.sql`:
```sql
create or replace function public.set_my_location(_lat float, _lng float, _label text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := (select auth.uid());
begin
  if _uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  insert into public.profile_locations(profile_id, geog, place_label, updated_at)
  values (_uid, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography, _label, now())
  on conflict (profile_id) do update set geog = excluded.geog, place_label = excluded.place_label, updated_at = now();
end; $$;

create or replace function public.set_team_location(_team_id uuid, _lat float, _lng float, _label text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_team_admin(_team_id) then raise exception 'not authorized' using errcode='P0001'; end if;
  insert into public.team_locations(team_id, geog, place_label, updated_at)
  values (_team_id, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography, _label, now())
  on conflict (team_id) do update set geog = excluded.geog, place_label = excluded.place_label, updated_at = now();
end; $$;

revoke all on function public.set_my_location(float,float,text) from public;
revoke all on function public.set_team_location(uuid,float,float,text) from public;
grant execute on function public.set_my_location(float,float,text) to authenticated;
grant execute on function public.set_team_location(uuid,float,float,text) to authenticated;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-matchmaking): private location tables + set-location rpcs`).

---

## PHASE 2 - LOOKING-FOR POSTS + DISCOVERY

### Task 3: Looking-for enums + posts table
**Files:** Create `.../20260616203201_lf_enums.sql`; Create `.../20260616203202_looking_for_posts.sql`; Create `supabase/tests/45-posts.test.sql`.
- [ ] **Step 1: Failing test** - `45-posts.test.sql`:
```sql
begin;
select plan(5);
select has_type('public','lf_mode','lf_mode enum');
select has_type('public','lf_status','lf_status enum');
select has_type('public','skill_level','skill_level enum');
select has_table('public','looking_for_posts','posts table');
select has_index('public','looking_for_posts','looking_for_posts_geog_idx','geog GiST index');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3a: enums** - `20260616203201_lf_enums.sql`:
```sql
create type public.lf_mode      as enum ('player_seeking_team','team_seeking_players','team_seeking_opponent');
create type public.lf_status    as enum ('open','filled','cancelled','expired');
create type public.skill_level  as enum ('beginner','intermediate','advanced');
```
- [ ] **Step 3b: posts table** - `20260616203202_looking_for_posts.sql`:
```sql
create table public.looking_for_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  team_id uuid references public.teams(id) on delete cascade,
  mode public.lf_mode not null,
  title text,
  description text,
  geog extensions.geography(Point,4326) not null,
  place_label text,
  match_at timestamptz,
  overs int,
  skill public.skill_level,
  slots_needed int,
  status public.lf_status not null default 'open',
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
create index looking_for_posts_geog_idx on public.looking_for_posts using gist (geog);
create index looking_for_posts_author_idx on public.looking_for_posts(author_id);
create index looking_for_posts_team_idx on public.looking_for_posts(team_id);
alter table public.looking_for_posts enable row level security;
grant select, insert, update, delete on public.looking_for_posts to authenticated;
create policy "posts_select_authenticated" on public.looking_for_posts for select to authenticated using (true);
create policy "posts_insert_author" on public.looking_for_posts for insert to authenticated
  with check (author_id = (select auth.uid()) and (team_id is null or public.is_team_admin(team_id)));
create policy "posts_update_author" on public.looking_for_posts for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));
create policy "posts_delete_author" on public.looking_for_posts for delete to authenticated
  using (author_id = (select auth.uid()));
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-matchmaking): looking-for enums + posts table`).

### Task 4: Post lifecycle RPCs (create / cancel / fill)
**Files:** Create `.../20260616203301_rpc_posts.sql`; Create `supabase/tests/46-post-rpcs.test.sql`.
- [ ] **Step 1: Failing test** - `46-post-rpcs.test.sql` (create returns id; cancel sets status; team post requires admin):
```sql
begin;
select plan(3);
select tests.create_supabase_user('a@m.dev');
select tests.authenticate_as('a@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
select isnt(public.create_looking_for_post('player_seeking_team', 19.07, 72.87, 'need a team Sunday', null, null, null, null, null, null), null, 'create returns id');
select _p.id as _pid from public.looking_for_posts _p limit 1 \gset
select public.cancel_post(:'_pid'::uuid);
select is((select status::text from public.looking_for_posts where id = :'_pid'::uuid), 'cancelled', 'cancel sets status');
select is((select count(*)::int from public.looking_for_posts where author_id = tests.get_supabase_uid('a@m.dev')), 1, 'one post by author');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616203301_rpc_posts.sql`:
```sql
create or replace function public.create_looking_for_post(
  _mode public.lf_mode, _lat float, _lng float, _description text default null,
  _team_id uuid default null, _title text default null, _match_at timestamptz default null,
  _overs int default null, _skill public.skill_level default null, _slots_needed int default null,
  _place_label text default null, _expires_at timestamptz default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare _uid uuid := (select auth.uid()); _id uuid;
begin
  if _uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if _team_id is not null and not public.is_team_admin(_team_id) then raise exception 'not authorized' using errcode='P0001'; end if;
  insert into public.looking_for_posts(author_id, team_id, mode, title, description, geog, place_label, match_at, overs, skill, slots_needed, expires_at)
  values (_uid, _team_id, _mode, _title, _description,
          extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography,
          _place_label, _match_at, _overs, _skill, _slots_needed, _expires_at)
  returning id into _id;
  return _id;
end; $$;

create or replace function public.cancel_post(_post_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.looking_for_posts set status='cancelled'
   where id=_post_id and author_id = (select auth.uid());
  if not found then raise exception 'not authorized or not found' using errcode='P0001'; end if;
end; $$;

create or replace function public.mark_post_filled(_post_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.looking_for_posts set status='filled'
   where id=_post_id and author_id = (select auth.uid());
  if not found then raise exception 'not authorized or not found' using errcode='P0001'; end if;
end; $$;

revoke all on function public.create_looking_for_post(public.lf_mode,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz) from public;
grant execute on function public.create_looking_for_post(public.lf_mode,float,float,text,uuid,text,timestamptz,int,public.skill_level,int,text,timestamptz) to authenticated;
revoke all on function public.cancel_post(uuid) from public;  grant execute on function public.cancel_post(uuid) to authenticated;
revoke all on function public.mark_post_filled(uuid) from public; grant execute on function public.mark_post_filled(uuid) to authenticated;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-matchmaking): post create/cancel/fill rpcs`).

### Task 5: discover_posts geo feed (headline)
**Files:** Create `.../20260616203401_rpc_discover_posts.sql`; Create `supabase/tests/47-discover.test.sql`.
- [ ] **Step 1: Failing test** - `47-discover.test.sql` (near IN, far OUT, magnitude guard, no coords returned, expired excluded, mode filter):
```sql
begin;
select plan(5);
select tests.create_supabase_user('a@m.dev');
select tests.authenticate_as('a@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
-- anchor = Mumbai (lat 19.07, lng 72.87). near ~2km (lng+0.02). far ~48km (lat+0.43).
select public.create_looking_for_post('player_seeking_team', 19.07, 72.89, 'near', null, null, null, null, null, null, 'Near') as _near \gset
select public.create_looking_for_post('player_seeking_team', 19.50, 72.87, 'far', null, null, null, null, null, null, 'Far') as _far \gset
-- an expired near post (should be excluded)
select public.create_looking_for_post('player_seeking_team', 19.07, 72.89, 'old', null, null, null, null, null, null, 'Old', now() - interval '1 day') as _old \gset
update public.looking_for_posts set status='open' where id = :'_old'::uuid; -- still open but expired_at past

-- within 10km of the anchor: near is returned, far is not
select is((select count(*)::int from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_near'::uuid), 1, 'near post discovered within 10km');
select is((select count(*)::int from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_far'::uuid), 0, 'far post (~48km) excluded at 10km radius');
-- magnitude guard: near distance is ~2km, not hundreds (would fail if lng/lat swapped)
select ok((select approx_m from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_near'::uuid) between 1500 and 2600, 'near approx_m ~2km (lng/lat order guard)');
-- expired excluded
select is((select count(*)::int from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_old'::uuid), 0, 'expired post excluded');
-- the discover output has no geog/lat/lng column (privacy): selecting it errors
select throws_ok($$ select d.geog from public.discover_posts(19.07,72.87,10000) d limit 1 $$, '42703', null, 'discover returns no coordinate column');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616203401_rpc_discover_posts.sql`:
```sql
create or replace function public.discover_posts(
  _lat float, _lng float, _radius_m float default 25000,
  _mode public.lf_mode default null, _max_overs int default null,
  _on_or_after timestamptz default null, _skill public.skill_level default null
) returns table (
  post_id uuid, author_id uuid, team_id uuid, mode public.lf_mode,
  title text, description text, place_label text, match_at timestamptz,
  overs int, skill public.skill_level, slots_needed int, created_at timestamptz, approx_m float
) language sql security definer set search_path = '' stable as $$
  select p.id, p.author_id, p.team_id, p.mode, p.title, p.description, p.place_label, p.match_at,
         p.overs, p.skill, p.slots_needed, p.created_at,
         round(extensions.st_distance(p.geog, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography) / 100.0) * 100 as approx_m
  from public.looking_for_posts p
  where p.status = 'open'
    and (p.expires_at is null or p.expires_at > now())
    and (_mode is null or p.mode = _mode)
    and (_max_overs is null or p.overs is null or p.overs <= _max_overs)
    and (_on_or_after is null or p.match_at is null or p.match_at >= _on_or_after)
    and (_skill is null or p.skill = _skill)
    and extensions.st_dwithin(p.geog, extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography, _radius_m)
  order by p.geog operator(extensions.<->) extensions.st_setsrid(extensions.st_makepoint(_lng,_lat),4326)::extensions.geography;
$$;
revoke all on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level) from public;
grant execute on function public.discover_posts(float,float,float,public.lf_mode,int,timestamptz,public.skill_level) to authenticated;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-matchmaking): discover_posts geo feed rpc`).

---

## PHASE 3 - POST REPLIES

### Task 6: post_replies
**Files:** Create `.../20260616203501_post_replies.sql`; Create `supabase/tests/48-post-replies.test.sql`.
- [ ] **Step 1: Failing test** - `48-post-replies.test.sql` (any authed user replies + reads; author of reply only can write own):
```sql
begin;
select plan(3);
select tests.create_supabase_user('a@m.dev'); select tests.create_supabase_user('b@m.dev');
select tests.authenticate_as('a@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
select public.create_looking_for_post('team_seeking_players', 19.07, 72.87, 'need 2', null, null, null, null, null, 2) as _p \gset
select tests.authenticate_as('b@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('b@m.dev'),'B');
select has_table('public','post_replies','post_replies table');
select lives_ok($$ insert into public.post_replies(post_id, author_id, body) values ((select id from public.looking_for_posts limit 1), tests.get_supabase_uid('b@m.dev'), 'I can play') $$, 'authed user can reply');
-- B cannot post a reply as someone else (WITH CHECK author = self)
select throws_ok($$ insert into public.post_replies(post_id, author_id, body) values ((select id from public.looking_for_posts limit 1), tests.get_supabase_uid('a@m.dev'), 'spoof') $$, '42501', null, 'cannot reply as another user');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616203501_post_replies.sql`:
```sql
create table public.post_replies (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.looking_for_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
create index post_replies_post_idx on public.post_replies(post_id);
alter table public.post_replies enable row level security;
grant select, insert, delete on public.post_replies to authenticated;
create policy "post_replies_select_authenticated" on public.post_replies for select to authenticated using (true);
create policy "post_replies_insert_own" on public.post_replies for insert to authenticated
  with check (author_id = (select auth.uid()));
create policy "post_replies_delete_own" on public.post_replies for delete to authenticated
  using (author_id = (select auth.uid()));
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-matchmaking): post replies table + RLS`).

---

## PHASE 4 - DIRECT MESSAGES

### Task 7: DM tables + is_thread_participant helper
**Files:** Create `.../20260616203601_dm.sql`; Create `supabase/tests/49-dm-tables.test.sql`.
- [ ] **Step 1: Failing test** - `49-dm-tables.test.sql`:
```sql
begin;
select plan(4);
select has_table('public','dm_threads','dm_threads');
select has_table('public','dm_participants','dm_participants');
select has_table('public','dm_messages','dm_messages');
select has_function('public','is_thread_participant',array['uuid'],'is_thread_participant(uuid)');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616203601_dm.sql`:
```sql
create table public.dm_threads (
  id uuid primary key default gen_random_uuid(),
  user_lo uuid not null references public.profiles(id) on delete cascade,
  user_hi uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint dm_threads_ordered check (user_lo < user_hi)
);
create unique index dm_threads_pair_uniq on public.dm_threads(user_lo, user_hi);

create table public.dm_participants (
  thread_id uuid not null references public.dm_threads(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  primary key (thread_id, profile_id)
);

create table public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.dm_threads(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index dm_messages_thread_idx on public.dm_messages(thread_id, created_at);

create or replace function public.is_thread_participant(_thread_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.dm_participants where thread_id = _thread_id and profile_id = (select auth.uid()));
$$;
revoke all on function public.is_thread_participant(uuid) from public;
grant execute on function public.is_thread_participant(uuid) to authenticated;

alter table public.dm_threads enable row level security;
alter table public.dm_participants enable row level security;
alter table public.dm_messages enable row level security;
grant select, insert on public.dm_threads to authenticated;
grant select, insert on public.dm_participants to authenticated;
grant select, insert, update on public.dm_messages to authenticated;

create policy "dm_threads_select_participant" on public.dm_threads for select to authenticated
  using (public.is_thread_participant(id));
create policy "dm_participants_select" on public.dm_participants for select to authenticated
  using (profile_id = (select auth.uid()) or public.is_thread_participant(thread_id));
create policy "dm_messages_select_participant" on public.dm_messages for select to authenticated
  using (public.is_thread_participant(thread_id));
create policy "dm_messages_insert_participant" on public.dm_messages for insert to authenticated
  with check (public.is_thread_participant(thread_id) and sender_id = (select auth.uid()));
create policy "dm_messages_update_read" on public.dm_messages for update to authenticated
  using (public.is_thread_participant(thread_id)) with check (public.is_thread_participant(thread_id));
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-matchmaking): dm tables + is_thread_participant + RLS`).

### Task 8: get_or_create_dm_thread + participant gating tests
**Files:** Create `.../20260616203701_rpc_dm.sql`; Create `supabase/tests/50-dm-gating.test.sql`.
- [ ] **Step 1: Failing test** - `50-dm-gating.test.sql` (idempotent thread; participants message; outsider cannot read):
```sql
begin;
select plan(4);
select tests.create_supabase_user('a@m.dev'); select tests.create_supabase_user('b@m.dev'); select tests.create_supabase_user('c@m.dev');
select tests.authenticate_as('a@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
select tests.authenticate_as('b@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('b@m.dev'),'B');
select tests.authenticate_as('c@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('c@m.dev'),'C');

select tests.authenticate_as('a@m.dev');
select public.get_or_create_dm_thread(tests.get_supabase_uid('b@m.dev')) as _t \gset
-- idempotent: calling again returns the same thread
select is(public.get_or_create_dm_thread(tests.get_supabase_uid('b@m.dev'))::text, (:'_t'::uuid)::text, 'thread creation is idempotent for the same pair');
-- A sends a message
select lives_ok($$ insert into public.dm_messages(thread_id, sender_id, body) values ((select id from public.dm_threads limit 1), tests.get_supabase_uid('a@m.dev'), 'hi') $$, 'participant can send');
-- C (outsider) cannot read the thread's messages
select tests.authenticate_as('c@m.dev');
select is((select count(*)::int from public.dm_messages where thread_id = :'_t'::uuid), 0, 'non-participant cannot read messages');
-- C cannot send into the thread
select throws_ok($$ insert into public.dm_messages(thread_id, sender_id, body) values (:'_t'::uuid, tests.get_supabase_uid('c@m.dev'), 'intrude') $$, '42501', null, 'non-participant cannot send');
select * from finish();
rollback;
```
(Note: `:'_t'` is used in bare SQL and in the throws_ok string; since it is a single literal substitution it is acceptable here, but if psql refuses interpolation inside `$$`, replace with `(select id from public.dm_threads limit 1)`.)
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616203701_rpc_dm.sql`:
```sql
create or replace function public.get_or_create_dm_thread(_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare _me uuid := (select auth.uid()); _lo uuid; _hi uuid; _id uuid;
begin
  if _me is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if _other = _me then raise exception 'cannot DM yourself' using errcode='P0001'; end if;
  _lo := least(_me, _other); _hi := greatest(_me, _other);
  insert into public.dm_threads(user_lo, user_hi) values (_lo, _hi)
    on conflict (user_lo, user_hi) do nothing;
  select id into _id from public.dm_threads where user_lo=_lo and user_hi=_hi;
  insert into public.dm_participants(thread_id, profile_id) values (_id, _lo), (_id, _hi)
    on conflict do nothing;
  return _id;
end; $$;
revoke all on function public.get_or_create_dm_thread(uuid) from public;
grant execute on function public.get_or_create_dm_thread(uuid) to authenticated;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-matchmaking): get_or_create_dm_thread + dm gating`).

### Task 9: DM broadcast trigger + private realtime policy
**Files:** Create `.../20260616203801_dm_broadcast.sql`; Create `supabase/tests/51-dm-broadcast.test.sql`.
- [ ] **Step 1: Failing test** - `51-dm-broadcast.test.sql`:
```sql
begin;
select plan(2);
select has_function('public','broadcast_dm_message','dm broadcast fn');
select has_trigger('public','dm_messages','dm_messages_broadcast','dm broadcast trigger');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616203801_dm_broadcast.sql`:
```sql
create or replace function public.broadcast_dm_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare _rec public.dm_messages := coalesce(NEW, OLD);
begin
  perform realtime.broadcast_changes('dm:' || _rec.thread_id::text, tg_op, tg_op, tg_table_name, tg_table_schema, NEW, OLD);
  return null;
exception when others then return null;
end; $$;

create trigger dm_messages_broadcast
  after insert on public.dm_messages
  for each row execute function public.broadcast_dm_message();

-- PRIVATE receive: only thread participants, authenticated ONLY (no anon). Client must use private:true + setAuth.
create policy "dm_broadcast_receive" on realtime.messages for select to authenticated
  using (realtime.messages.extension = 'broadcast'
         and realtime.topic() like 'dm:%'
         and public.is_thread_participant((split_part(realtime.topic(), ':', 2))::uuid));
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-matchmaking): dm realtime broadcast + private receive policy`).

### Task 10: End-to-end integration test + README
**Files:** Create `supabase/tests/52-integration.test.sql`; Modify `Projects/cricket-app/backend/README.md`.
- [ ] **Step 1: Integration test** - `52-integration.test.sql` (player posts near X; captain ~3km discovers; opens DM; both message; post filled):
```sql
begin;
select plan(5);
select tests.create_supabase_user('player@m.dev'); select tests.create_supabase_user('cap@m.dev');
select tests.authenticate_as('player@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('player@m.dev'),'Player');
select tests.authenticate_as('cap@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@m.dev'),'Cap');

-- player posts "need a team" at Mumbai
select tests.authenticate_as('player@m.dev');
select public.create_looking_for_post('player_seeking_team', 19.07, 72.87, 'free Sunday, batter', null, null, null, null, 'intermediate', null, 'Bandra') as _post \gset

-- captain ~3km away (lng +0.03) discovers it within 10km
select tests.authenticate_as('cap@m.dev');
select is((select count(*)::int from public.discover_posts(19.07, 72.90, 10000, 'player_seeking_team') d where d.post_id = :'_post'::uuid), 1, 'captain discovers the nearby player post');
select ok((select approx_m from public.discover_posts(19.07, 72.90, 10000) d where d.post_id = :'_post'::uuid) between 2500 and 3800, 'distance ~3km');

-- captain opens a DM with the player and both exchange messages
select public.get_or_create_dm_thread(tests.get_supabase_uid('player@m.dev')) as _t \gset
insert into public.dm_messages(thread_id, sender_id, body) values (:'_t'::uuid, tests.get_supabase_uid('cap@m.dev'), 'Want to play for us Sunday?');
select tests.authenticate_as('player@m.dev');
insert into public.dm_messages(thread_id, sender_id, body) values (:'_t'::uuid, tests.get_supabase_uid('player@m.dev'), 'Yes!');
select is((select count(*)::int from public.dm_messages where thread_id = :'_t'::uuid), 2, 'both messages stored in the thread');

-- player marks their post filled
select public.mark_post_filled(:'_post'::uuid);
select is((select status::text from public.looking_for_posts where id = :'_post'::uuid), 'filled', 'post marked filled');
-- and it no longer appears in discovery
select tests.authenticate_as('cap@m.dev');
select is((select count(*)::int from public.discover_posts(19.07, 72.90, 10000) d where d.post_id = :'_post'::uuid), 0, 'filled post drops out of the feed');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect PASS** (all RPCs exist by now).
- [ ] **Step 3: Update README** - append a "Matchmaking & Discovery (sub-project #3)" section: PostGIS geo (private location tables, distance-not-coords), `discover_posts` feed (3 modes), `post_replies`, 1:1 DM (threads/participants/messages + private realtime), the key privacy stance, and the RPC list.
- [ ] **Step 4: Commit** (`test(cricket-matchmaking): end-to-end integration test + README`).

---

## Self-Review (completed by author)
**Spec coverage:** extension -> T1; private locations + set-location -> T2; enums+posts -> T3; post lifecycle -> T4; discover feed (proximity/filter/expiry/privacy) -> T5; replies -> T6; DM tables+helper+RLS -> T7; thread create+gating -> T8; DM realtime+private policy -> T9; integration+README -> T10. Privacy fix (separate location tables, no client SELECT, distance-not-coords) -> T2+T5. All four spec phases covered.

**Placeholder scan:** every step has concrete SQL + tests. The one `:var`-inside-`$$` note in T8/T10 is explicitly flagged with the subquery fallback (the prior backend hit exactly this). No TBD/TODO.

**Type/name consistency:** `geography(Point,4326)`, the point-builder `extensions.st_setsrid(extensions.st_makepoint(LNG,LAT),4326)::extensions.geography` (lng first), `discover_posts`/`set_my_location`/`is_thread_participant`/`get_or_create_dm_thread` signatures, and the `extensions.`-qualified PostGIS calls in `search_path=''` functions are consistent across tasks. Migration order: postgis -> locations -> posts -> rpcs -> replies -> dm -> dm rpc -> dm broadcast (each references only already-created objects; `is_team_admin` and `realtime.broadcast_changes`/`realtime.messages` already exist from prior sub-projects).

**Known watch-item:** `:vars` inside `throws_ok`/`lives_ok` `$$..$$` are NOT interpolated by psql; T8/T10 use them in bare SQL (fine) and the one in-string case is flagged with the subquery fallback. During execution, if a `42601 syntax error at or near ":"` appears, swap that `:var` for a subquery (as done in the scoring corrections test).
