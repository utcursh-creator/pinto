begin;
select plan(4);
-- SEC-8: add_tournament_team requires the organizer to admin the team.
-- TOUR-5: standings list EVERY entered team at P0 before any match is played.
select tests.create_supabase_user('org@s.dev');
select tests.create_supabase_user('rando@s.dev');

select tests.authenticate_as('org@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('org@s.dev'), 'Org');
select public.create_tournament('Cup', 20, 1, 2) as _t \gset
select public.create_team('X', 'C') as _x \gset
select public.create_team('Y', 'C') as _y \gset

-- the organizer admins X and Y (they created them) -> can enter both
select public.add_tournament_team(:'_t'::uuid, :'_x'::uuid, 'A');
select public.add_tournament_team(:'_t'::uuid, :'_y'::uuid, 'A');

-- a team the organizer does NOT admin cannot be enrolled (SEC-8)
select tests.authenticate_as('rando@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('rando@s.dev'), 'Rando');
select public.create_team('Z', 'C') as _z \gset
select tests.authenticate_as('org@s.dev');
-- `(select id from public.tournaments limit 1)` used to stand in for the
-- tournament here. It picked WHATEVER tournament the local DB happened to hold,
-- so the moment a device-journey run left one behind, the call tripped the
-- ORGANIZER check ("not authorized") and never reached the team-admin guard
-- this test is named after - and throws_ok, given only an errcode, was happy.
-- Name the ids.
select throws_ok(
  format($$ select public.add_tournament_team(%L, %L, 'A') $$, :'_t', :'_z'),
  'P0001', 'you must be an admin of this team to enter it',
  'the organizer cannot enter a team they do not admin');

-- TOUR-5: with no matches played, both entered teams appear at P0
select is((select jsonb_array_length(
    public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows')), 2,
  'both entered teams appear in the table before any match');
select is((select (e->>'points')::int from jsonb_array_elements(
    public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') e
    where e->>'team_id' = :'_x'), 0, 'X starts at 0 points');
select is((select (e->>'played')::int from jsonb_array_elements(
    public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') e
    where e->>'team_id' = :'_y'), 0, 'Y starts at 0 played');

select * from finish();
rollback;
