begin;
select plan(5);

select tests.create_supabase_user('cap@test.dev');
select tests.create_supabase_user('rando@test.dev');
select tests.authenticate_as('cap@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('cap@test.dev'), 'Cap');
select tests.authenticate_as('rando@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('rando@test.dev'), 'Rando');

-- Captain creates a team via RPC and becomes captain
select tests.authenticate_as('cap@test.dev');
select isnt(public.create_team('Mavericks', 'Pune'), null, 'create_team returns a team id');
select is((select count(*)::int from public.teams where name = 'Mavericks'), 1, 'team row exists');

-- Any authenticated user can read the team
select tests.authenticate_as('rando@test.dev');
select is((select name from public.teams where name = 'Mavericks'), 'Mavericks', 'teams are readable by any authed user');

-- A non-admin's rename is filtered out by teams_update_admin's USING qual: 0 rows, no exception.
select lives_ok(
  $$ update public.teams set name = 'Hacked' where name = 'Mavericks' $$,
  'non-admin team rename runs but is a silent no-op under RLS');
select is(
  (select name from public.teams where city = 'Pune' limit 1),
  'Mavericks', 'team name is unchanged after non-admin attempted update');

select * from finish();
rollback;
