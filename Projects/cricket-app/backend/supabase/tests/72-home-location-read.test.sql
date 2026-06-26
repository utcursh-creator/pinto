-- Reading back a persisted home location: my_home_location() returns the
-- caller's own point as lat/lng (the geog column is PostGIS binary, unusable
-- raw); team_home_location() returns a team's ground to its members only.
begin;
select plan(6);
select tests.create_supabase_user('u1@s.dev');
select tests.create_supabase_user('u2@s.dev');
select tests.authenticate_as('u1@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('u1@s.dev'),'U1');

-- A) my_home_location round-trips lat/lng/label
select public.set_my_location(19.07, 72.87, 'Mumbai');
select is((select round(lat::numeric,2) from public.my_home_location()), 19.07::numeric,
  'my_home_location returns the stored latitude');
select is((select round(lng::numeric,2) from public.my_home_location()), 72.87::numeric,
  'my_home_location returns the stored longitude');
select is((select label from public.my_home_location()), 'Mumbai',
  'my_home_location returns the place label');

-- B) a user with no saved location gets no row
select tests.authenticate_as('u2@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('u2@s.dev'),'U2');
select is((select count(*)::int from public.my_home_location()), 0,
  'no saved location -> no row');

-- C) team_home_location: a member can read their team ground
select tests.authenticate_as('u1@s.dev');
select public.create_team('Strikers','Pune') as _t \gset
select public.set_team_location(:'_t'::uuid, 18.52, 73.85, 'Pune ground');
select is((select round(lat::numeric,2) from public.team_home_location(:'_t'::uuid)), 18.52::numeric,
  'team_home_location returns the team ground latitude to a member');

-- D) a non-member cannot read the team ground
select tests.authenticate_as('u2@s.dev');
select throws_ok($$ select * from public.team_home_location(
  (select id from public.teams where name='Strikers')) $$,
  'P0001', null, 'a non-member cannot read the team ground');

select * from finish();
rollback;
