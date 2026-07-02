begin;
select plan(8);
-- TEAM-13: team_career_stats gives the W/L line from completed matches.
-- TEAM-11: request_to_join + respond_join_request open teams to strangers with
-- admin consent.
select tests.create_supabase_user('cap@t.dev');
select tests.create_supabase_user('joiner@t.dev');

select tests.authenticate_as('cap@t.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@t.dev'), 'Cap');
select public.create_team('Strikers', 'C') as _a \gset
select public.create_team('Rivals', 'C') as _b \gset

-- one win for Strikers, one loss (Rivals win)
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m1 \gset
select public.set_match_result(:'_m1'::uuid, 'win_by_runs', :'_a'::uuid);
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m2 \gset
select public.set_match_result(:'_m2'::uuid, 'win_by_wickets', :'_b'::uuid);

select is((public.team_career_stats(:'_a'::uuid)->>'played')::int, 2,
  'the team played 2 completed matches');
select is((public.team_career_stats(:'_a'::uuid)->>'won')::int, 1,
  'one win counted');
select is((public.team_career_stats(:'_a'::uuid)->>'lost')::int, 1,
  'one loss counted');

-- TEAM-11: a stranger requests to join; the captain is notified
select tests.authenticate_as('joiner@t.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('joiner@t.dev'), 'Joiner');
select isnt(public.request_to_join(:'_a'::uuid), null, 'a stranger can request to join');
select throws_ok(
  format($$ select public.request_to_join(%L) $$, :'_a'::uuid),
  'P0001', 'request already pending', 'a duplicate pending request is refused');

-- a non-admin cannot respond
select throws_ok(
  $$ select public.respond_join_request(
       (select id from public.team_join_requests limit 1), true) $$,
  'P0001', 'not authorized', 'a non-admin cannot respond to a request');

-- the captain approves -> the requester becomes a member + was notified
select tests.authenticate_as('cap@t.dev');
select is((select count(*)::int from public.notifications where type = 'join_request'),
  1, 'the captain was notified of the request');
select public.respond_join_request(
  (select id from public.team_join_requests where team_id = :'_a'::uuid), true);
select is(
  (select count(*)::int from public.team_members
    where team_id = :'_a'::uuid
      and profile_id = tests.get_supabase_uid('joiner@t.dev')),
  1, 'approval makes the requester a member');

select * from finish();
rollback;
