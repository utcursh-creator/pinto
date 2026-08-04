begin;
select plan(6);
-- Whole-system review #2 (2026-07-28), findings 20 / 21 / 29 / 60: the app's
-- hottest queries had no index that could serve them.
--
-- This asserts the PLANNER USES an index for the real predicate, not merely
-- that some index exists on the column. For the search case that distinction is
-- the entire point: no btree can serve an unanchored `ilike '%q%'`, so
-- "there is an index on display_name" would pass while every keystroke still
-- seq-scanned the table. Only a trigram GIN index changes the plan.
--
-- enable_seqscan is turned off so the tiny test tables do not make a seq scan
-- look cheapest. That does NOT force an index scan - where no index can serve
-- the predicate, Postgres still seq-scans (at an absurd cost), which is exactly
-- what makes these assertions discriminating rather than tautological.
set local enable_seqscan = off;

create or replace function pg_temp.plan_of(_sql text) returns text
language plpgsql as $$
declare _line text; _out text := '';
begin
  for _line in execute 'explain (costs off) ' || _sql loop
    _out := _out || _line || E'\n';
  end loop;
  return _out;
end $$;

-- Minimal but REAL rows so the planner has statistics to reason about.
-- profiles.id FKs to auth.users, so the users come first.
select tests.create_supabase_user('owner@ix.dev');
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
select gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'ix' || g || '@ix.dev', 'x',
       now(), now(), now()
from generate_series(1, 40) g;

insert into public.profiles(id, display_name, handle)
select u.id, 'Player ' || row_number() over (order by u.id),
       'player' || row_number() over (order by u.id)
from auth.users u where u.email like 'ix%@ix.dev';

select tests.get_supabase_uid('owner@ix.dev') as _own \gset
-- teams.created_by FKs to PROFILES, not auth.users
insert into public.profiles(id, display_name, handle)
values (:'_own'::uuid, 'Index Owner', 'indexowner');
insert into public.teams(id, name, city, created_by)
select gen_random_uuid(), 'Club ' || g, 'Pune', :'_own'::uuid
from generate_series(1, 40) g;

select id as _ta from public.teams where name like 'Club %' order by name limit 1 \gset
select id as _tb from public.teams where name like 'Club %' order by name offset 1 limit 1 \gset
insert into public.matches(id, team_a_id, team_b_id, owner_id, scorer_id,
                           overs_limit, balls_per_over, rules, status)
select gen_random_uuid(), :'_ta'::uuid, :'_tb'::uuid, :'_own'::uuid, :'_own'::uuid,
       20, 6, '{}'::jsonb,
       (case when g % 10 = 0 then 'live' else 'complete' end)::public.match_status
from generate_series(1, 60) g;

analyze public.profiles;
analyze public.teams;
analyze public.matches;
analyze public.match_squad;

-- 1-3. search: unanchored ILIKE must reach a trigram index
select matches(
  pg_temp.plan_of($$ select id from public.profiles where display_name ilike '%laye%' $$),
  'profiles_display_name_trgm_idx',
  'searching a player by display name uses the trigram index, not a full scan');
select matches(
  pg_temp.plan_of($$ select id from public.profiles where handle ilike '%laye%' $$),
  'profiles_handle_trgm_idx',
  'searching a player by handle uses the trigram index');
select matches(
  pg_temp.plan_of($$ select id from public.teams where name ilike '%lub%' $$),
  'teams_name_trgm_idx',
  'searching a club by name uses the trigram index');

-- 4. the public Watch-live list - reachable without signing in, so the most
--    exposed query in the app
select matches(
  pg_temp.plan_of($$
    select id from public.matches
     where status in ('live','innings_break')
     order by created_at desc limit 20 $$),
  'matches_live_created_idx',
  'the public live-match list uses the partial index instead of scanning and '
  'sorting every match ever played');

-- 5. team-scoped fixtures
select matches(
  pg_temp.plan_of(format($$ select id from public.matches where team_a_id = %L $$, :'_ta')),
  'matches_team_a_idx',
  'a club''s fixtures use an index on team_a_id');

-- 6. career stats walk the squad by player
select matches(
  pg_temp.plan_of($$
    select id from public.match_squad
     where team_member_id = '00000000-0000-0000-0000-000000000001' $$),
  'match_squad_member_idx',
  'career stats reach match_squad by team_member_id through its own index, not '
  'the composite unique where it is the second column');

select * from finish();
rollback;
