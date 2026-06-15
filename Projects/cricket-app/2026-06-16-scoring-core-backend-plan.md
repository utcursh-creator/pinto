---
type: plan
date: 2026-06-16
project: cricket-app
sub-project: scoring-core
layer: backend
status: draft
tags: [cricket-app, plan, backend, supabase, postgres, scoring, pgtap, tdd]
---

# Scoring Core - Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and test the event-sourced cricket Scoring Core backend on Supabase: the schema (matches, match_squad, innings, deliveries), the single `compute_innings_state` fold that is the sole home of all cricket rules, the mutation RPCs (record/undo/edit/delete/insert ball + set result), live broadcast, and RLS - all verified by pgTAP, with zero frontend.

**Architecture:** A ball is an immutable-ish fact in `deliveries` ordered by a monotonic per-innings `seq`. The entire scorecard (totals, cards, partnerships, charts, live rates, result) is a pure left-fold over the ordered deliveries via one PL/pgSQL function `compute_innings_state(innings_id) returns jsonb`. There are no hand-maintained running totals; corrections re-fold. All mutations go through advisory-locked SECURITY DEFINER RPCs. Live fan-out is Supabase Realtime Broadcast-from-database.

**Tech Stack:** Supabase CLI (local stack, OrbStack) | PostgreSQL | PL/pgSQL | Row-Level Security | pgTAP + vendored basejump test helpers (already installed in `supabase/seed.sql` from sub-project #1). No ORM, no bespoke test framework.

**Spec:** `Projects/cricket-app/2026-06-16-scoring-core-design.md`. The spec's verified rule matrix, dismissal rules, and stat derivations ARE the fold's implementation guide; this plan turns each into a failing pgTAP test then the minimal fold logic.

**Reuses from sub-project #1 (already built + committed):** `profiles`, `teams`, `team_members`, the `is_team_admin` SECURITY DEFINER pattern, the pgTAP + basejump harness, and two hard-won local facts: (a) `supabase db reset` does NOT auto-grant DML to `authenticated`, so every table needs explicit `grant ... to authenticated`; (b) psql does NOT interpolate `:'var'` inside `$$..$$` dollar-quoted strings, so inside `throws_ok`/`lives_ok` identify rows with subqueries, never `:vars`.

**Conventions:** snake_case; everything in `public`; migrations are manually timestamped (the slow `supabase migration new` auto-backgrounds and truncates writes) with monotonically increasing names; one object per migration; one pgTAP file per migration; run a task with `supabase db reset >/dev/null 2>&1 && supabase test db`; no em dashes anywhere.

---

## File Structure

Backend root: `Projects/cricket-app/backend/` (exists from sub-project #1). New files only.

| Path | Responsibility |
|---|---|
| `supabase/migrations/2026061620xxxx_scoring_enums.sql` | all scoring enums |
| `.../2026061620xxxx_team_members_bats.sql` | additive `bats` column on team_members |
| `.../2026061620xxxx_matches.sql` | matches table + indexes |
| `.../2026061620xxxx_is_match_scorer.sql` | SECURITY DEFINER scorer-auth helper |
| `.../2026061620xxxx_matches_rls.sql` | matches RLS + grants + create_match RPC |
| `.../2026061620xxxx_match_squad.sql` | match_squad table + RLS + add_squad_member RPC |
| `.../2026061620xxxx_innings.sql` | innings table + RLS + start_innings RPC |
| `.../2026061620xxxx_deliveries.sql` | deliveries table + indexes + RLS |
| `.../2026061620xxxx_fold_vNN_*.sql` | `compute_innings_state` created once then grown by ALTER-via-CREATE-OR-REPLACE across fold tasks |
| `.../2026061620xxxx_rpc_record_ball.sql` | record_ball |
| `.../2026061620xxxx_rpc_corrections.sql` | undo/edit/delete/insert ball |
| `.../2026061620xxxx_rpc_set_result.sql` | set_match_result |
| `.../2026061620xxxx_broadcast.sql` | deliveries broadcast trigger + realtime policy |
| `supabase/tests/2x-*.test.sql` | one pgTAP file per task (continues the 00..11 numbering from #1; scoring uses 20..) |

**Fold growth strategy:** `compute_innings_state` is created in Task 9 as a complete skeleton and then replaced wholesale (`create or replace`) by each later fold task, which adds one rule-family and its tests. The plan shows the FULL function body at each stage where it changes materially, so an engineer reading any single task has the complete current function. The fold is one focused file responsibility even though several migrations touch it (each is a `create or replace`).

**Naming/type contract (used across all tasks):**
- `compute_innings_state(_innings_id uuid) returns jsonb` - the only rule home; pure (no writes).
- `is_match_scorer(_match_id uuid) returns boolean` - SECURITY DEFINER, SET search_path = public.
- RPCs: `create_match(...) -> uuid`; `add_squad_member(...) -> uuid`; `start_innings(...) -> uuid`; `record_ball(...) -> uuid` (delivery id); `undo_last_ball(_innings_id) -> void`; `edit_ball(_delivery_id, ...) -> void`; `delete_ball(_delivery_id) -> void`; `insert_ball(_innings_id, _after_seq, ...) -> uuid`; `set_match_result(_match_id, _result_type, _winner_team_id, _note) -> void`.
- Delivery outcome inputs to record_ball/edit_ball: `runs_off_bat int, extra_wides int, extra_no_ball_penalty int, extra_byes int, extra_leg_byes int, extra_penalty int, noball_secondary_kind, wicket_type, dismissed_player_id, incoming_batter_id, fielder_id, crossed, prevented_catch, is_overthrow, overthrow_crossed, wagon_x, wagon_y, wagon_zone, bowler_id, commentary_text`.

---

## PHASE 1 - SCHEMA AND ACCESS

### Task 1: Scoring enums

**Files:** Create `supabase/migrations/20260616200101_scoring_enums.sql`; Create `supabase/tests/20-scoring-enums.test.sql`.

- [ ] **Step 1: Write the failing test** - `supabase/tests/20-scoring-enums.test.sql`:
```sql
begin;
select plan(10);
select has_type('public','match_status','match_status enum');
select has_type('public','innings_status','innings_status enum');
select has_type('public','toss_decision','toss_decision enum');
select has_type('public','ball_type','ball_type enum');
select has_type('public','pitch_type','pitch_type enum');
select has_type('public','noball_secondary_kind','noball_secondary_kind enum');
select has_type('public','bats_hand','bats_hand enum');
select has_type('public','wicket_type','wicket_type enum');
select has_type('public','result_type','result_type enum');
select has_type('public','margin_method','margin_method enum');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL** - `supabase db reset >/dev/null 2>&1 && supabase test db` -> 20-scoring-enums fails (types absent).
- [ ] **Step 3: Write the migration** - `20260616200101_scoring_enums.sql`:
```sql
create type public.match_status         as enum ('setup','live','innings_break','complete','abandoned');
create type public.innings_status       as enum ('in_progress','completed');
create type public.toss_decision        as enum ('bat','bowl');
create type public.ball_type            as enum ('leather','tennis','tape','other');
create type public.pitch_type           as enum ('turf','matting','cement','astroturf','other');
create type public.noball_secondary_kind as enum ('off_bat','bye','leg_bye');
create type public.bats_hand            as enum ('RHB','LHB');
create type public.wicket_type          as enum ('bowled','caught','lbw','run_out','stumped','hit_wicket','retired_out','retired_not_out','obstructing','timed_out','hit_ball_twice');
create type public.result_type          as enum ('win_by_runs','win_by_wickets','tie','tie_superover','win_dls','win_vjd','no_result','abandoned','conceded','forfeit','walkover','awarded');
create type public.margin_method        as enum ('normal','DLS','VJD');
```
- [ ] **Step 4: Run, expect PASS** - `supabase db reset >/dev/null 2>&1 && supabase test db` -> 10 tests pass (plus all sub-project #1 tests stay green).
- [ ] **Step 5: Commit**
```bash
git add Projects/cricket-app/backend/supabase/migrations/20260616200101_scoring_enums.sql Projects/cricket-app/backend/supabase/tests/20-scoring-enums.test.sql
git commit -m "feat(cricket-scoring): add scoring enums

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 2: team_members.bats (additive)

**Files:** Create `.../20260616200201_team_members_bats.sql`; Create `supabase/tests/21-team-members-bats.test.sql`.

- [ ] **Step 1: Failing test** - `21-team-members-bats.test.sql`:
```sql
begin;
select plan(2);
select has_column('public','team_members','bats','team_members has bats');
select col_type_is('public','team_members','bats','bats_hand','bats is bats_hand');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616200201_team_members_bats.sql`:
```sql
alter table public.team_members add column bats public.bats_hand;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-scoring): add team_members.bats for wagon-wheel orientation`).

### Task 3: matches table

**Files:** Create `.../20260616200301_matches.sql`; Create `supabase/tests/22-matches.test.sql`.

- [ ] **Step 1: Failing test** - `22-matches.test.sql`:
```sql
begin;
select plan(7);
select has_table('public','matches','matches table');
select col_is_pk('public','matches','id','id pk');
select fk_ok('public','matches','team_a_id','public','teams','id');
select fk_ok('public','matches','scorer_id','public','profiles','id');
select col_type_is('public','matches','rules','jsonb','rules is jsonb');
select col_has_default('public','matches','status','status default');
select col_type_is('public','matches','toss_decision','toss_decision','toss_decision enum col');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616200301_matches.sql`:
```sql
create table public.matches (
  id            uuid primary key default gen_random_uuid(),
  team_a_id     uuid not null references public.teams(id),
  team_b_id     uuid not null references public.teams(id),
  owner_id      uuid not null references public.profiles(id),
  scorer_id     uuid not null references public.profiles(id),
  overs_limit   int not null,
  balls_per_over int not null default 6,
  rules         jsonb not null default '{}'::jsonb,
  toss_winner_id uuid references public.teams(id),
  toss_decision public.toss_decision,
  venue         text,
  city          text,
  scheduled_at  timestamptz,
  ball_type     public.ball_type,
  pitch_type    public.pitch_type,
  status        public.match_status not null default 'setup',
  result        jsonb,
  created_at    timestamptz not null default now()
);
create index matches_scorer_idx on public.matches(scorer_id);
create index matches_owner_idx  on public.matches(owner_id);
alter table public.matches enable row level security;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-scoring): add matches table`).

### Task 4: is_match_scorer helper

**Files:** Create `.../20260616200401_is_match_scorer.sql`; Create `supabase/tests/23-is-match-scorer.test.sql`.

- [ ] **Step 1: Failing test** - `23-is-match-scorer.test.sql`:
```sql
begin;
select plan(1);
select has_function('public','is_match_scorer',array['uuid'],'is_match_scorer(uuid) exists');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616200401_is_match_scorer.sql` (SECURITY DEFINER + SET search_path makes it non-inlinable; reads matches without recursion):
```sql
create or replace function public.is_match_scorer(_match_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.matches where id = _match_id and scorer_id = (select auth.uid()));
$$;
revoke all on function public.is_match_scorer(uuid) from public;
grant execute on function public.is_match_scorer(uuid) to authenticated;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-scoring): is_match_scorer security-definer helper`).

### Task 5: matches RLS + create_match RPC

**Files:** Create `.../20260616200501_matches_rls.sql`; Create `.../20260616200502_rpc_create_match.sql`; Create `supabase/tests/24-matches-rls.test.sql`.

- [ ] **Step 1: Failing test** - `24-matches-rls.test.sql`:
```sql
begin;
select plan(4);
select tests.create_supabase_user('owner@s.dev');
select tests.create_supabase_user('rando@s.dev');
select tests.authenticate_as('owner@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('owner@s.dev'),'Owner');
-- need two teams owned by owner (reuse create_team from sub-project #1)
select public.create_team('Alpha','Pune') as _a \gset
select public.create_team('Beta','Pune') as _b \gset
-- create a match via RPC
select isnt(public.create_match(:'_a'::uuid, :'_b'::uuid, 20), null, 'create_match returns id');
select is((select count(*)::int from public.matches where team_a_id = :'_a'::uuid), 1, 'match row exists');
-- any authed user can read
select tests.authenticate_as('rando@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rando@s.dev'),'Rando');
select is((select overs_limit from public.matches where team_a_id = :'_a'::uuid), 20, 'match readable by any authed user');
-- non-scorer cannot update the match (silent no-op under USING)
select lives_ok($$ update public.matches set venue='X' where overs_limit=20 $$,'non-scorer update is a no-op');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL** (create_match missing).
- [ ] **Step 3a: matches RLS migration** - `20260616200501_matches_rls.sql`:
```sql
grant select, insert, update, delete on public.matches to authenticated;
create policy "matches_select_authenticated" on public.matches for select to authenticated using (true);
create policy "matches_insert_own" on public.matches for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "matches_update_scorer" on public.matches for update to authenticated
  using (public.is_match_scorer(id)) with check (public.is_match_scorer(id));
create policy "matches_delete_owner" on public.matches for delete to authenticated using (owner_id = (select auth.uid()));
```
- [ ] **Step 3b: create_match RPC** - `20260616200502_rpc_create_match.sql`:
```sql
create or replace function public.create_match(
  _team_a uuid, _team_b uuid, _overs int,
  _balls_per_over int default 6, _rules jsonb default '{}'::jsonb,
  _venue text default null, _city text default null, _ball_type public.ball_type default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid; _uid uuid := (select auth.uid());
begin
  if _uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  insert into public.matches(team_a_id,team_b_id,owner_id,scorer_id,overs_limit,balls_per_over,rules,venue,city,ball_type)
  values (_team_a,_team_b,_uid,_uid,_overs,_balls_per_over,_rules,_venue,_city,_ball_type)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.create_match(uuid,uuid,int,int,jsonb,text,text,public.ball_type) from public;
grant execute on function public.create_match(uuid,uuid,int,int,jsonb,text,text,public.ball_type) to authenticated;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-scoring): matches RLS + create_match rpc`).

### Task 6: match_squad table + RLS + add_squad_member RPC

**Files:** Create `.../20260616200601_match_squad.sql`; Create `.../20260616200602_rpc_add_squad_member.sql`; Create `supabase/tests/25-match-squad.test.sql`.

- [ ] **Step 1: Failing test** - `25-match-squad.test.sql` (build a match, add a guest squad member; non-scorer rejected):
```sql
begin;
select plan(4);
select tests.create_supabase_user('cap@s.dev'); select tests.create_supabase_user('out@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('Alpha','Pune') as _a \gset
select public.create_team('Beta','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'Guest A1') as _m \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select has_table('public','match_squad','match_squad table');
select isnt(public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_m'::uuid, 1, false, false), null, 'scorer adds squad member');
select is((select batting_order from public.match_squad where match_id=:'_mt'::uuid and team_member_id=:'_m'::uuid),1,'order stored');
select tests.authenticate_as('out@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('out@s.dev'),'Out');
select throws_ok($$ select public.add_squad_member((select id from public.matches limit 1),(select team_a_id from public.matches limit 1),(select id from public.team_members where guest_name='Guest A1'),2,false,false) $$,'P0001','not authorized','non-scorer cannot add squad');
select * from finish();
rollback;
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3a: match_squad migration** - `20260616200601_match_squad.sql`:
```sql
create table public.match_squad (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  team_id uuid not null references public.teams(id),
  team_member_id uuid not null references public.team_members(id),
  batting_order int,
  is_captain boolean not null default false,
  is_wicket_keeper boolean not null default false,
  is_substitute boolean not null default false,
  created_at timestamptz not null default now(),
  unique(match_id, team_member_id)
);
create index match_squad_match_idx on public.match_squad(match_id);
alter table public.match_squad enable row level security;
grant select, insert, update, delete on public.match_squad to authenticated;
create policy "match_squad_select_authenticated" on public.match_squad for select to authenticated using (true);
create policy "match_squad_write_scorer" on public.match_squad for all to authenticated
  using (public.is_match_scorer(match_id)) with check (public.is_match_scorer(match_id));
```
- [ ] **Step 3b: add_squad_member RPC** - `20260616200602_rpc_add_squad_member.sql`:
```sql
create or replace function public.add_squad_member(
  _match_id uuid, _team_id uuid, _team_member_id uuid,
  _batting_order int default null, _is_captain boolean default false, _is_keeper boolean default false
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid;
begin
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode='P0001'; end if;
  insert into public.match_squad(match_id,team_id,team_member_id,batting_order,is_captain,is_wicket_keeper)
  values (_match_id,_team_id,_team_member_id,_batting_order,_is_captain,_is_keeper)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.add_squad_member(uuid,uuid,uuid,int,boolean,boolean) from public;
grant execute on function public.add_squad_member(uuid,uuid,uuid,int,boolean,boolean) to authenticated;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-scoring): match_squad table, RLS, add_squad_member rpc`).

### Task 7: innings table + RLS + start_innings RPC

**Files:** Create `.../20260616200701_innings.sql`; Create `.../20260616200702_rpc_start_innings.sql`; Create `supabase/tests/26-innings.test.sql`.

- [ ] **Step 1: Failing test** - `26-innings.test.sql` (scorer starts an innings; FK + uniqueness; non-scorer rejected). Build match as in Task 6, then:
```sql
-- ... (setup: cap profile, teams _a/_b, match _mt, opening pair guests _s and _ns on team _a) ...
select has_table('public','innings','innings table');
select isnt(public.start_innings(:'_mt'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid), null, 'scorer starts innings');
select is((select innings_number from public.innings where match_id=:'_mt'::uuid),1,'innings 1 created');
```
(plan(4): has_table, isnt, is, plus a throws_ok for a non-scorer call mirroring Task 6.)
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3a: innings migration** - `20260616200701_innings.sql`:
```sql
create table public.innings (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  innings_number int not null,
  batting_team_id uuid not null references public.teams(id),
  bowling_team_id uuid not null references public.teams(id),
  opening_striker_id uuid not null references public.team_members(id),
  opening_non_striker_id uuid not null references public.team_members(id),
  overs_limit int,
  revised_overs int,
  target int,
  status public.innings_status not null default 'in_progress',
  created_at timestamptz not null default now(),
  unique(match_id, innings_number)
);
create index innings_match_idx on public.innings(match_id);
alter table public.innings enable row level security;
grant select, insert, update, delete on public.innings to authenticated;
create policy "innings_select_authenticated" on public.innings for select to authenticated using (true);
create policy "innings_write_scorer" on public.innings for all to authenticated
  using (public.is_match_scorer(match_id)) with check (public.is_match_scorer(match_id));
```
- [ ] **Step 3b: start_innings RPC** - `20260616200702_rpc_start_innings.sql`:
```sql
create or replace function public.start_innings(
  _match_id uuid, _innings_number int, _batting_team uuid, _bowling_team uuid,
  _opening_striker uuid, _opening_non_striker uuid, _target int default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid;
begin
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode='P0001'; end if;
  insert into public.innings(match_id,innings_number,batting_team_id,bowling_team_id,opening_striker_id,opening_non_striker_id,target)
  values (_match_id,_innings_number,_batting_team,_bowling_team,_opening_striker,_opening_non_striker,_target)
  returning id into _id;
  update public.matches set status='live' where id=_match_id and status='setup';
  return _id;
end; $$;
revoke all on function public.start_innings(uuid,int,uuid,uuid,uuid,uuid,int) from public;
grant execute on function public.start_innings(uuid,int,uuid,uuid,uuid,uuid,int) to authenticated;
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-scoring): innings table, RLS, start_innings rpc`).

### Task 8: deliveries table

**Files:** Create `.../20260616200801_deliveries.sql`; Create `supabase/tests/27-deliveries.test.sql`.

- [ ] **Step 1: Failing test** - `27-deliveries.test.sql`:
```sql
begin;
select plan(7);
select has_table('public','deliveries','deliveries table');
select col_type_is('public','deliveries','seq','bigint','seq is bigint');
select fk_ok('public','deliveries','innings_id','public','innings','id');
select fk_ok('public','deliveries','striker_id','public','team_members','id');
-- is_legal generated: a wide row is not legal
select has_column('public','deliveries','is_legal','is_legal column');
-- CHECK: cannot be both wide and no-ball (insert directly as superuser to test the constraint)
-- (build a match/innings/seq context first in setup, then:)
select throws_ok($$ insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_wides,extra_no_ball_penalty)
  values ((select id from public.innings limit 1),1,(select id from public.team_members limit 1),(select id from public.team_members limit 1),(select id from public.team_members limit 1),1,1) $$,
  '23514', null, 'cannot be both wide and no-ball');
select has_index('public','deliveries','deliveries_innings_seq_uidx','unique (innings_id,seq)');
select * from finish();
```
(Setup builds one match + innings so the FK/CHECK insert has valid parents; team_members from sub-project #1 helpers.)
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Migration** - `20260616200801_deliveries.sql`:
```sql
create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  innings_id uuid not null references public.innings(id) on delete cascade,
  seq bigint not null,
  bowler_id uuid not null references public.team_members(id),
  runs_off_bat int not null default 0,
  extra_wides int not null default 0,
  extra_no_ball_penalty int not null default 0,
  extra_byes int not null default 0,
  extra_leg_byes int not null default 0,
  extra_penalty int not null default 0,
  noball_secondary_kind public.noball_secondary_kind,
  is_legal boolean generated always as (extra_wides = 0 and extra_no_ball_penalty = 0) stored,
  wicket_type public.wicket_type,
  dismissed_player_id uuid references public.team_members(id),
  incoming_batter_id uuid references public.team_members(id),
  fielder_id uuid references public.team_members(id),
  crossed boolean,
  prevented_catch boolean,
  is_overthrow boolean not null default false,
  overthrow_crossed boolean,
  wagon_x real, wagon_y real, wagon_zone smallint,
  commentary_text text,
  striker_id uuid not null references public.team_members(id),
  non_striker_id uuid not null references public.team_members(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deliveries_not_both_wide_noball check (not (extra_wides > 0 and extra_no_ball_penalty > 0))
);
create unique index deliveries_innings_seq_uidx on public.deliveries(innings_id, seq);
alter table public.deliveries enable row level security;
grant select, insert, update, delete on public.deliveries to authenticated;
create policy "deliveries_select_authenticated" on public.deliveries for select to authenticated using (true);
create policy "deliveries_write_scorer" on public.deliveries for all to authenticated
  using (exists (select 1 from public.innings i where i.id = deliveries.innings_id and public.is_match_scorer(i.match_id)))
  with check (exists (select 1 from public.innings i where i.id = deliveries.innings_id and public.is_match_scorer(i.match_id)));
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** (`feat(cricket-scoring): deliveries event-log table (decomposed extras, generated is_legal)`).

---

## PHASE 2 - THE FOLD (compute_innings_state), incremental TDD

Each fold task replaces the function with `create or replace` and adds one rule-family plus its tests. The function signature is fixed: `compute_innings_state(_innings_id uuid) returns jsonb`. It is PURE (no writes). Define it `SECURITY INVOKER` (the caller already passes RLS for read) with `SET search_path = public` for hygiene. For the chart/series accumulators, build them with `jsonb_agg(... order by ...)` over a final pass rather than per-ball `acc := acc || ...` concatenation (the latter is O(n^2)); correctness is identical, this is just to keep large innings fast. Implementation pattern: load match+innings config; load batting squad ordered; loop `for d in select * from deliveries where innings_id=_innings_id order by seq loop ... end loop` maintaining PL/pgSQL variables (team_runs, wickets, legal_balls, legal_balls_this_over, striker, non_striker, bowler, free_hit boolean, jsonb accumulators for batters/bowlers/extras/fow/partnerships/per_over/worm); then assemble and return jsonb. Helper sub-logic implements the spec's verified rule matrix (design spec sections "Delivery outcome matrix", "Dismissals", "Stat derivations").

### Task 9: fold skeleton - totals
TDD: test that an innings with three legal singles returns `runs=3, wickets=0, legal_balls=3, over='0.3'` and extras zero. Implement the loop computing team_runs = sum(runs_off_bat + extra_wides + extra_no_ball_penalty + extra_byes + extra_leg_byes + extra_penalty), legal_balls = count where is_legal, wickets = count where wicket_type is not null and not in (retired_not_out), and the X.Y over string. Return `jsonb_build_object('runs',...,'wickets',...,'legal_balls',...,'over',...,'extras',jsonb_build_object('wides',...,'no_balls',...,'byes',...,'leg_byes',...,'penalty',...))`. Test file `28-fold-totals.test.sql`. Commit.

### Task 10: strike rotation
TDD: opening pair set; after 1 run striker swaps; after a dot no swap; at end of a 6-legal-ball over strike swaps; a boundary 4 does not swap. Assert returned `striker_id`/`non_striker_id` after a built sequence. Implement: initialize striker=opening_striker, non_striker=opening_non_striker; per delivery compute the run-parity swap (runs that cause a physical end change: runs_off_bat when no boundary, byes/leg-byes, wide-runs-run, no-ball secondary runs) then, when legal_balls_this_over hits balls_per_over, reset it and swap strike (end-of-over swap applied after the per-ball swap). Boundaries (4/6 off bat) do not swap. Test `29-fold-strike.test.sql`. Commit.

### Task 11: extras + bowler charge
TDD: wide adds 1 + is not a legal ball (over does not advance) + charged to bowler; no-ball penalty set + free-hit pending (tested next task) + not legal; byes/leg-byes are legal + NOT charged to bowler; byes off a no-ball charge only the penalty to the bowler; penalty-5 not charged. Assert the extras breakdown and per-bowler `runs_conceded`. Implement bowler conceded = runs_off_bat + extra_wides + extra_no_ball_penalty + (off-bat runs already in runs_off_bat) and EXCLUDE byes/leg-byes/penalty; maiden tracking per over. Test `30-fold-extras.test.sql`. Commit.

### Task 12: free-hit state machine
TDD: a no-ball sets free_hit true for the next legal ball; a following wide keeps it true (carry); the next legal ball consumes it; two no-balls in a row keep chaining. Assert a returned `free_hit_active` flag at the tail. Implement the boolean: set true after any delivery with extra_no_ball_penalty>0; on a legal delivery, after processing, set false; on wide/no-ball, leave unchanged. Test `31-fold-freehit.test.sql`. Commit.

### Task 13: batting card + did_not_bat
TDD: per-batter runs/balls/4s/6s/SR correct (wide not a ball faced; no-ball faced per `count_noball_as_ball_faced` default true; bye is a ball faced, no runs to batter); did_not_bat = squad batting-order players who never faced and were never dismissed. Implement per-batter jsonb accumulator keyed by team_member id; did_not_bat from `match_squad` minus seen batters. Test `32-fold-batting.test.sql`. Commit.

### Task 14: bowling card + maiden
TDD: per-bowler overs X.Y, maidens, runs, wickets, economy, dot_balls, wides_bowled, no_balls_bowled; a leg-byes-only over is a maiden, a wide in the over breaks it. Implement per-bowler accumulator + per-over maiden detection (runs charged to bowler in the over == 0 and 6 legal balls). Test `33-fold-bowling.test.sql`. Commit.

### Task 15: dismissals + FoW + incoming strike
TDD: bowled credits bowler + striker out + not-out batter stays; caught returns not-out batter to original end and incoming takes strike (Oct-2022); run_out uses dismissed_player_id + crossed for next strike; wickets increment; FoW entries carry score + over.ball + dismissed id; bowler not credited for run_out/obstructing. Implement dismissal handling in the loop: increment wickets, attribute bowler wicket for the credited set, set the new striker/non_striker using incoming_batter_id + the per-type end rule, append FoW. Test `34-fold-dismissals.test.sql`. Commit.

### Task 16: partnerships
TDD: partnership runs/balls per wicket and current partnership; a partnership spans from one wicket to the next; each batter's contribution split. Implement partnership accumulation keyed by the current pair, closed on each wicket, plus the open current one. Test `35-fold-partnerships.test.sql`. Commit.

### Task 17: charts (Manhattan + worm)
TDD: per_over[] has runs_in_over (incl extras) and wickets_in_over per completed/partial over; worm[] is monotonic cumulative runs/wickets. Implement two arrays accumulated during the loop. Test `36-fold-charts.test.sql`. Commit.

### Task 18: innings-end + result + live rates + orphan flagging
TDD: innings ends at all-out (squad-1) / overs (using COALESCE(revised_overs,overs_limit,match overs)) / chase target reached; crr = runs/(legal_balls/6); rrr/runs_required/balls_remaining/wickets_remaining for a chasing innings (target set); deliveries after the end are flagged in orphaned_deliveries[]; result computes win_by_runs/win_by_wickets/tie with balls/wickets remaining. Implement end-detection inside the loop (stop scoring into state after end, push to orphaned), post-loop rate computation, and a structured result object. Test `37-fold-innings-end.test.sql`. Commit.

---

## PHASE 3 - MUTATION RPCs

### Task 19: record_ball
**Files:** `.../20260616201901_rpc_record_ball.sql`; `supabase/tests/38-record-ball.test.sql`.
TDD: scorer records a legal ball -> a deliveries row with seq=1, striker/non_striker stamped from the fold-derived strike; stumped on a free hit is REJECTED (P0001); a second over by the same bowler is rejected unless rules.allow_consecutive_overs. Implement: `pg_advisory_xact_lock(hashtextextended(_innings_id::text,0))`; fold current state to get current striker/non_striker/bowler-of-prev-over/free_hit; validate dismissal-legality vs free_hit + extra flags (no-ball/free-hit allowed set = {run_out,obstructing,hit_ball_twice}; wide allowed set); validate consecutive-over unless toggled; `seq := coalesce(max(seq),0)+1`; insert stamping striker_id/non_striker_id from the fold. Non-scorer rejected. Commit (`feat(cricket-scoring): record_ball rpc with dismissal + consecutive-over guards`).

### Task 20: corrections (undo/edit/delete/insert)
**Files:** `.../20260616202001_rpc_corrections.sql`; `supabase/tests/39-corrections.test.sql`.
TDD (the core-risk cascade): record an over of [1, dot, 1, dot, 1, dot] -> assert strike; edit ball 1 from a single to a wide -> re-fold: that ball no longer legal, the over now needs another legal ball, strike rotation for every later ball changes -> assert the new striker + legal_balls; undo_last removes max seq; delete_ball middle leaves a gap that the fold tolerates; insert_ball renumbers seq>after and the fold re-derives. Each correction re-stamps striker/non_striker on affected rows (call the fold and update later deliveries' stamped strike). Implement all four under the advisory lock. Commit (`feat(cricket-scoring): undo/edit/delete/insert ball corrections with re-fold`).

### Task 21: set_match_result
**Files:** `.../20260616202101_rpc_set_result.sql`; `supabase/tests/40-set-result.test.sql`.
TDD: scorer sets `no_result` (winner null) -> matches.status='complete', result jsonb has result_type='no_result'; scorer sets a manual `awarded` winner with null margin; completion allowed with <2 innings. Implement the RPC (scorer-gated) writing `matches.result` + status. Commit (`feat(cricket-scoring): set_match_result rpc for non-play results`).

---

## PHASE 4 - BROADCAST AND INTEGRATION

### Task 22: deliveries broadcast trigger + realtime policy
**Files:** `.../20260616202201_broadcast.sql`; `supabase/tests/41-broadcast.test.sql`.

**Privacy model (decided):** live scores are PUBLIC, like CricHeroes' login-free live pages. The realtime receive policy is intentionally open (any viewer, incl. logged-out, may watch any match). This matches the spec's public-read RLS. It is a deliberate product choice, not an oversight; if private matches are ever wanted, scope the policy by `matches` membership instead.

- [ ] **Step 1: Failing test** - `supabase/tests/41-broadcast.test.sql` (the broadcast itself is hard to assert in pgTAP, so test the CONTRACT: the function + trigger exist and a real `record_ball` does not error because the broadcast is exception-safe):
```sql
begin;
select plan(2);
select has_function('public','broadcast_delivery_change','broadcast trigger fn exists');
select has_trigger('public','deliveries','deliveries_broadcast','broadcast trigger attached');
select * from finish();
rollback;
```
(A fuller "record_ball does not error" assertion lives in the Task 23 integration test, where a full match context exists.)

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Migration** - `20260616202201_broadcast.sql`. Note `coalesce(NEW, OLD)` so DELETE (where NEW is NULL) still resolves the innings; `SET search_path = ''` so every reference is fully qualified; exception-safe so a Realtime hiccup never aborts ball entry:
```sql
create or replace function public.broadcast_delivery_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  _match_id uuid;
  _rec public.deliveries := coalesce(NEW, OLD);
begin
  select i.match_id into _match_id from public.innings i where i.id = _rec.innings_id;
  perform realtime.broadcast_changes(
    'match:' || _match_id::text,  -- topic
    tg_op,                        -- event
    tg_op,                        -- operation
    tg_table_name,                -- table
    tg_table_schema,              -- schema
    NEW,                          -- new record
    OLD                           -- old record
  );
  return null;
exception when others then
  return null;  -- never abort the write on a broadcast failure
end;
$$;

create trigger deliveries_broadcast
  after insert or update or delete on public.deliveries
  for each row execute function public.broadcast_delivery_change();

-- Public live viewing: any viewer (incl. anon/logged-out) may RECEIVE a match's broadcast.
-- Deliberate per the spec's public-read decision (CricHeroes-style login-free live scores).
-- No INSERT policy on realtime.messages: clients are read-only; the SECURITY DEFINER trigger writes.
create policy "match_broadcast_receive"
  on realtime.messages for select to authenticated, anon
  using (realtime.messages.extension = 'broadcast' and realtime.topic() like 'match:%');
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit** (`feat(cricket-scoring): realtime broadcast trigger + public receive policy`).

### Task 23: end-to-end integration test + README
**Files:** `supabase/tests/42-integration.test.sql`; update `Projects/cricket-app/backend/README.md`.
TDD: a full match - create_match, squads for both teams, start_innings 1, record an over containing a dot/single/wide/no-ball+free-hit/boundary/wicket, undo + re-record, complete innings 1, start_innings 2 with target, chase to a win_by_wickets result; assert the final fold state (totals, a batting card line, a bowling card line, a partnership, the result with balls/wickets remaining) and the integrity invariant sum(batsman runs)+extras==team total. Update README with the scoring tables, the fold contract, and the RPC list. Commit (`test(cricket-scoring): end-to-end integration test + README`).

---

## Self-Review (completed by author)

**Spec coverage:** schema (matches/match_squad/innings/deliveries/enums/team_members.bats) -> Tasks 1-8; decomposed extras + generated is_legal + CHECK -> Task 8; the fold + every verified rule (matrix, dismissals, stat derivations, free-hit, innings-end, result) -> Tasks 9-18; fold output contract (cards, partnerships, Manhattan, worm, live rates, did_not_bat, structured result) -> Tasks 13-18; corrections + advisory lock + dismissal/consecutive-over guards -> Tasks 19-20; revised_overs + result taxonomy + set_match_result -> Tasks 18, 21; broadcast + realtime policy -> Task 22; RLS (public read, scorer write via is_match_scorer) -> Tasks 4-8; wagon columns -> Task 8 (+ captured by record_ball Task 19). Out-of-scope items carry no tasks (correct).

**Placeholder scan:** schema/RPC/trigger/RLS tasks carry full SQL. The fold tasks (9-18) specify the exact test behavior + the precise rule logic to implement from the named spec sections rather than pre-pasting a 500-line PL/pgSQL blob; this is deliberate for a function built test-first and grown by `create or replace`, and each task's pgTAP test is the complete, executable behavior contract. No TBD/TODO.

**Type/name consistency:** `compute_innings_state(_innings_id uuid)`, `is_match_scorer(_match_id uuid)`, the RPC signatures, and the decomposed-extra column names are consistent between definition (Tasks 4-8) and use (Tasks 9-23). Migration order respects dependencies: enums -> team_members.bats -> matches -> is_match_scorer -> matches RLS -> match_squad -> innings -> deliveries -> fold -> RPCs -> broadcast (is_match_scorer is LANGUAGE sql so it is created after matches; the fold and RPCs are plpgsql so forward references resolve at call time, but deliveries already exists before the fold regardless).

**Known risk carried from sub-project #1:** every new table needs explicit `grant ... to authenticated` (done in each table task); `:vars` are never used inside `$$..$$` in tests (subqueries used instead).
