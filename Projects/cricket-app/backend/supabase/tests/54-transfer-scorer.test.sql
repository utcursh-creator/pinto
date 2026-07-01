begin;
select plan(11);

-- users + own profiles
select tests.create_supabase_user('scorer@m.dev');
select tests.create_supabase_user('mate@m.dev');
select tests.create_supabase_user('rando@m.dev');
select tests.create_supabase_user('neutral@m.dev');
select tests.authenticate_as('scorer@m.dev');  insert into public.profiles(id,display_name) values (tests.get_supabase_uid('scorer@m.dev'),'Scorer');
select tests.authenticate_as('mate@m.dev');     insert into public.profiles(id,display_name) values (tests.get_supabase_uid('mate@m.dev'),'Mate');
select tests.authenticate_as('rando@m.dev');    insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rando@m.dev'),'Rando');
select tests.authenticate_as('neutral@m.dev');  insert into public.profiles(id,display_name) values (tests.get_supabase_uid('neutral@m.dev'),'Neutral');

-- scorer captains team A, mate captains team B
select tests.authenticate_as('scorer@m.dev');
select public.create_team('Team A') as _ta \gset
select tests.authenticate_as('mate@m.dev');
select public.create_team('Team B') as _tb \gset

-- scorer creates the match (status defaults to 'setup'); scorer is the match scorer
select tests.authenticate_as('scorer@m.dev');
select public.create_match(:'_ta'::uuid, :'_tb'::uuid, 20) as _m \gset

-- 1. current scorer transfers to a member of the OPPONENT team (asymmetric allowed)
select lives_ok(
  $$ select public.transfer_scorer((select id from public.matches limit 1), tests.get_supabase_uid('mate@m.dev')) $$,
  'current scorer transfers to a member of the opponent team');
select is((select scorer_id from public.matches where id = :'_m'::uuid), tests.get_supabase_uid('mate@m.dev'), 'scorer_id is now mate');

-- 2. team-A admin (caller=scorer), who is NOT the current scorer (mate is), transfers back to scorer
select lives_ok(
  $$ select public.transfer_scorer((select id from public.matches limit 1), tests.get_supabase_uid('scorer@m.dev')) $$,
  'a team admin who is not the current scorer can transfer');
select is((select scorer_id from public.matches where id = :'_m'::uuid), tests.get_supabase_uid('scorer@m.dev'), 'scorer_id is back to scorer');

-- Task 5: the role flip is honoured by is_match_scorer (what deliveries_write_scorer / matches_update_scorer gate on)
select tests.authenticate_as('scorer@m.dev');
select ok(public.is_match_scorer(:'_m'::uuid), 'the current scorer passes is_match_scorer (can write)');
select tests.authenticate_as('mate@m.dev');
select ok(not public.is_match_scorer(:'_m'::uuid), 'a former scorer no longer passes is_match_scorer');

-- 3. unauthorized caller (neither scorer nor admin of either team)
select tests.authenticate_as('rando@m.dev');
select throws_ok(
  $$ select public.transfer_scorer((select id from public.matches limit 1), tests.get_supabase_uid('mate@m.dev')) $$,
  '42501', null, 'a non-scorer non-admin cannot transfer');

-- 4. authorized caller, but new scorer is not a member of either team
select tests.authenticate_as('scorer@m.dev');
select throws_ok(
  $$ select public.transfer_scorer((select id from public.matches limit 1), tests.get_supabase_uid('rando@m.dev')) $$,
  'P0001', null, 'cannot transfer to a non-member of either team');

-- 5. idempotent no-op when new == current and current is eligible
select lives_ok(
  $$ select public.transfer_scorer((select id from public.matches limit 1), tests.get_supabase_uid('scorer@m.dev')) $$,
  'idempotent no-op when new scorer equals the current eligible scorer');

-- 6. status guard: once the match is complete, transfer is refused
update public.matches set status='complete' where id = :'_m'::uuid;
select throws_ok(
  $$ select public.transfer_scorer((select id from public.matches limit 1), tests.get_supabase_uid('mate@m.dev')) $$,
  'P0001', null, 'cannot transfer once the match is complete');

-- 7. validate-always: an INELIGIBLE self no-op still raises (neutral is the current
--    scorer but on neither team). create_match now requires a team admin (SEC-5),
--    so an admin creates the match and scoring is handed to neutral directly.
select tests.authenticate_as('scorer@m.dev');
select public.create_match(:'_ta'::uuid, :'_tb'::uuid, 20) as _m2 \gset
update public.matches set scorer_id = tests.get_supabase_uid('neutral@m.dev') where id = :'_m2'::uuid;
select tests.authenticate_as('neutral@m.dev');
select throws_ok(
  $$ select public.transfer_scorer((select id from public.matches where scorer_id = tests.get_supabase_uid('neutral@m.dev')), tests.get_supabase_uid('neutral@m.dev')) $$,
  'P0001', null, 'an ineligible self no-op is still validated and rejected');

select * from finish();
rollback;
