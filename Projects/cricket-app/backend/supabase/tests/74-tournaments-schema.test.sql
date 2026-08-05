-- Tournaments schema: create_tournament (caller = organizer), add_tournament_team
-- (organizer-gated, setup-only), public read, organizer-only write (RLS).
begin;
select plan(8);
select tests.create_supabase_user('org@s.dev');
select tests.create_supabase_user('rando@s.dev');
select tests.authenticate_as('org@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('org@s.dev'),'Org');

select public.create_tournament('Summer Cup', 20, 2, 2) as _t \gset
select isnt(:'_t', null::uuid, 'create_tournament returns an id');
select is((select organizer_id from public.tournaments where id=:'_t'::uuid),
  tests.get_supabase_uid('org@s.dev'), 'caller becomes the organizer');
select is((select status::text from public.tournaments where id=:'_t'::uuid), 'setup',
  'status starts at setup');

select public.create_team('Alpha','C') as _a \gset
select public.create_team('Bravo','C') as _b \gset
select public.add_tournament_team(:'_t'::uuid, :'_a'::uuid, 'A');
select is((select group_label from public.tournament_teams
           where tournament_id=:'_t'::uuid and team_id=:'_a'::uuid), 'A',
  'add_tournament_team places the team in its group');

-- anon can read the public tournament
select tests.clear_authentication();
select is((select count(*)::int from public.tournaments where id=:'_t'::uuid), 1,
  'anon can SELECT a tournament');

-- a non-organizer cannot add a team
select tests.authenticate_as('rando@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rando@s.dev'),'Rando');
select throws_ok($$ select public.add_tournament_team(
  (select id from public.tournaments where name='Summer Cup'),
  (select id from public.teams where name='Bravo'), 'B') $$,
  'P0001', null, 'a non-organizer cannot add a team');

-- A non-organizer cannot UPDATE the tournament. This used to be a lives_ok -
-- "RLS filters the row out" - which left the client able to reach the table at
-- all. The drift guard in pgTAP 147 caught the grant while the review-#3 fix was
-- being written: the app only ever SELECTs tournaments, so an organiser could
-- have set status='complete' and named their own champion without playing the
-- bracket. Every write is an RPC now.
select throws_ok($$ update public.tournaments set name='Hacked' where name='Summer Cup' $$,
  '42501', null,
  'a non-organizer UPDATE is refused at permission, not merely filtered');
select is((select name from public.tournaments where id=:'_t'::uuid), 'Summer Cup',
  'RLS prevented the non-organizer from changing the tournament');

select * from finish();
rollback;
