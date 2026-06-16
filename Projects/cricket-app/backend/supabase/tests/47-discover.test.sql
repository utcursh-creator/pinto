begin;
select plan(5);
select tests.create_supabase_user('a@m.dev');
select tests.authenticate_as('a@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
-- anchor = Mumbai (lat 19.07, lng 72.87). near ~2km (lng+0.02). far ~48km (lat+0.43).
select public.create_looking_for_post('player_seeking_team', 19.07, 72.89, 'near', null, null, null, null, null, null, 'Near') as _near \gset
select public.create_looking_for_post('player_seeking_team', 19.50, 72.87, 'far', null, null, null, null, null, null, 'Far') as _far \gset
select public.create_looking_for_post('player_seeking_team', 19.07, 72.89, 'old', null, null, null, null, null, null, 'Old', now() - interval '1 day') as _old \gset

select is((select count(*)::int from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_near'::uuid), 1, 'near post discovered within 10km');
select is((select count(*)::int from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_far'::uuid), 0, 'far post (~48km) excluded at 10km');
select ok((select approx_m from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_near'::uuid) between 1500 and 2600, 'near approx_m ~2km (lng/lat order guard)');
select is((select count(*)::int from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_old'::uuid), 0, 'expired post excluded');
select throws_ok($$ select d.geog from public.discover_posts(19.07,72.87,10000) d limit 1 $$, '42703', null, 'discover returns no coordinate column');
select * from finish();
rollback;
