begin;
select plan(4);
select tests.create_supabase_user('a@m.dev');
select tests.create_supabase_user('b@m.dev');
select tests.authenticate_as('a@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
select tests.authenticate_as('b@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('b@m.dev'),'B');

-- A sets home near Mumbai (lng 72.87, lat 19.07)
select tests.authenticate_as('a@m.dev');
select public.set_my_location(19.07, 72.87, 'Mumbai');
select is((select count(*)::int from public.profile_locations where profile_id = tests.get_supabase_uid('a@m.dev')), 1, 'owner stored a location');

-- distance from A home to a point ~2km east (lng 72.89, lat 19.07) is ~2km -> guards lng/lat order
select ok(
  extensions.st_distance(
    (select geog from public.profile_locations where profile_id = tests.get_supabase_uid('a@m.dev')),
    extensions.st_setsrid(extensions.st_makepoint(72.89, 19.07),4326)::extensions.geography
  ) between 1500 and 2600, 'home point ~2km from a 0.02-deg-lng point (lng/lat order correct)');

-- B (non-owner) cannot read A's location row
select tests.authenticate_as('b@m.dev');
select is((select count(*)::int from public.profile_locations where profile_id = tests.get_supabase_uid('a@m.dev')), 0, 'non-owner cannot read another user location');

-- B sets + reads only their own
select public.set_my_location(18.52, 73.85, 'Pune');
select is((select count(*)::int from public.profile_locations where profile_id = tests.get_supabase_uid('b@m.dev')), 1, 'B reads own location');
select * from finish();
rollback;
