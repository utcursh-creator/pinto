begin;
select plan(7);
-- SEC-6 / MTCH-3: set_match_result validates the winner against the match's own
-- two teams, requires a winner for win results, nulls it for no-winner results,
-- and refuses to overwrite a match that is already final.
select tests.create_supabase_user('sc@s.dev');
select tests.authenticate_as('sc@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('sc@s.dev'), 'Sc');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
-- team X is NOT in the match; a result must never award it the win
select public.create_team('X', 'P') as _x \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset

-- a forged/foreign winner is rejected
select throws_ok(
  $$ select public.set_match_result(
       (select id from public.matches limit 1), 'win_by_runs',
       (select id from public.teams where name = 'X')) $$,
  'P0001', 'the winner must be one of the two teams in this match',
  'a winner that is not a participant is rejected');

-- a win result with no winner is rejected
select throws_ok(
  $$ select public.set_match_result((select id from public.matches limit 1), 'win_by_wickets') $$,
  'P0001', 'a winner is required for a win_by_wickets result',
  'a win result requires a winner');

-- a no-winner result nulls any winner that is passed, and completes the match
select public.set_match_result(:'_m'::uuid, 'no_result', :'_a'::uuid);
select is((select result->>'winner_team_id' from public.matches where id = :'_m'::uuid),
  null, 'no_result forces winner_team_id to null');
select is((select status::text from public.matches where id = :'_m'::uuid),
  'complete', 'no_result completes the match');

-- the match is now terminal: a second result is refused
select throws_ok(
  $$ select public.set_match_result((select id from public.matches limit 1), 'win_by_runs',
       (select team_a_id from public.matches limit 1)) $$,
  'P0001', 'this match already has a final result',
  'a completed match cannot be re-resulted');

-- a valid win to a real participant records the winner
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m2 \gset
select public.set_match_result(:'_m2'::uuid, 'win_by_runs', :'_b'::uuid, 'won by 12 runs');
select is((select result->>'winner_team_id' from public.matches where id = :'_m2'::uuid),
  (:'_b'::uuid)::text, 'a valid participant winner is recorded');
select is((select result->>'note' from public.matches where id = :'_m2'::uuid),
  'won by 12 runs', 'the human margin note is stored');

select * from finish();
rollback;
