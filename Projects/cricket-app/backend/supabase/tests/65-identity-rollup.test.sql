-- v_player_key / v_player_matches: a claimed profile rolls up across teams under
-- one key; an unclaimed guest keys by membership id; approve_guest_claim re-keys
-- the guest's history to the claimer with zero backfill (the view recomputes).
begin;
select plan(7);
select tests.create_supabase_user('cap@s.dev');
select tests.create_supabase_user('claimer@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');

-- cap creates two teams -> becomes a registered (profile_id) captain member of each
select public.create_team('Mumbai','M') as _t1 \gset
select public.create_team('Dadar','M')  as _t2 \gset
-- an unclaimed guest in team 1
select public.add_guest_member(:'_t1'::uuid,'Ghost') as _g \gset

-- A) the same profile rolls up under one player_key across both memberships
select is(
  (select count(distinct player_key)::int from public.v_player_key
   where member_id in (select id from public.team_members
                       where profile_id = tests.get_supabase_uid('cap@s.dev'))),
  1, 'a claimed profile rolls up to a single player_key across teams');
select is(
  (select distinct player_key from public.v_player_key
   where member_id in (select id from public.team_members
                       where profile_id = tests.get_supabase_uid('cap@s.dev'))),
  tests.get_supabase_uid('cap@s.dev'),
  'the rolled-up key is the profile id');

-- B) an unclaimed guest keys by its own membership id
select is(
  (select player_key from public.v_player_key where member_id = :'_g'::uuid),
  :'_g'::uuid, 'an unclaimed guest keys by membership id');
select is(
  (select profile_id from public.v_player_key where member_id = :'_g'::uuid),
  null::uuid, 'unclaimed guest has a null profile_id');

-- C) drive the claim: claimer requests, cap (team admin) approves -> re-key
select tests.authenticate_as('claimer@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('claimer@s.dev'),'Claimer');
select public.request_guest_claim(:'_g'::uuid);
select tests.authenticate_as('cap@s.dev');
select public.approve_guest_claim(:'_g'::uuid, tests.get_supabase_uid('claimer@s.dev'));

select is(
  (select player_key from public.v_player_key where member_id = :'_g'::uuid),
  tests.get_supabase_uid('claimer@s.dev'),
  'after approve_guest_claim the membership re-keys to the claimer (zero backfill)');
select is(
  (select profile_id from public.v_player_key where member_id = :'_g'::uuid),
  tests.get_supabase_uid('claimer@s.dev'),
  'the claimed membership now carries the claimer profile_id');

-- D) v_player_matches excludes non-final matches (setup/live); only complete/abandoned
select public.create_team('Bandra','M') as _t3 \gset
select public.create_match(:'_t1'::uuid,:'_t3'::uuid,20) as _mt \gset
select public.add_squad_member(:'_mt'::uuid,:'_t1'::uuid,
  (select id from public.team_members where profile_id = tests.get_supabase_uid('cap@s.dev') and team_id = :'_t1'::uuid));
select is(
  (select count(*)::int from public.v_player_matches
   where player_key = tests.get_supabase_uid('cap@s.dev') and match_id = :'_mt'::uuid),
  0, 'a setup-status match is NOT counted as played');

select * from finish();
rollback;
