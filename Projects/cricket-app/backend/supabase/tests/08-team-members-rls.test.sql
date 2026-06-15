begin;
select plan(5);

select tests.create_supabase_user('cap@test.dev');
select tests.create_supabase_user('player@test.dev');
select tests.create_supabase_user('outsider@test.dev');
select tests.authenticate_as('cap@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('cap@test.dev'), 'Cap');
select tests.authenticate_as('player@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('player@test.dev'), 'Player');
select tests.authenticate_as('outsider@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('outsider@test.dev'), 'Outsider');

-- Cap creates a team (RPC adds Cap as captain)
select tests.authenticate_as('cap@test.dev');
select public.create_team('Strikers', 'Mumbai') as _t \gset

-- is_team_admin true for the creator
select ok(public.is_team_admin(:'_t'::uuid), 'creator is team admin');

-- Cap can add a guest via RPC
select isnt(public.add_guest_member(:'_t'::uuid, 'Sachin (guest)'), null, 'admin can add a guest');

-- Outsider CANNOT add a guest to Cap's team
select tests.authenticate_as('outsider@test.dev');
select throws_ok(
  $$ select public.add_guest_member((select id from public.teams where name = 'Strikers'), 'Intruder') $$,
  'P0001', 'not authorized', 'non-admin cannot add a guest');

-- Outsider CANNOT directly insert a membership row either (RLS WITH CHECK -> 42501)
select throws_ok(
  $$ insert into public.team_members (team_id, profile_id)
     values ((select id from public.teams where name = 'Strikers'), tests.get_supabase_uid('outsider@test.dev')) $$,
  '42501', null, 'non-admin cannot self-insert into a roster');

-- Any authed user can READ the roster (captain + guest = 2)
select is((select count(*)::int from public.team_members
           where team_id = (select id from public.teams where name = 'Strikers')),
          2, 'roster (captain + guest) is readable');

select * from finish();
rollback;
