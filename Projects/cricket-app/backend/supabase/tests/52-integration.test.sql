begin;
select plan(5);
select tests.create_supabase_user('player@m.dev'); select tests.create_supabase_user('cap@m.dev');
select tests.authenticate_as('player@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('player@m.dev'),'Player');
select tests.authenticate_as('cap@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@m.dev'),'Cap');

-- player posts "need a team" at Mumbai (lat 19.07, lng 72.87)
select tests.authenticate_as('player@m.dev');
select public.create_looking_for_post('player_seeking_team', 19.07, 72.87, 'free Sunday, batter', null, null, null, null, 'intermediate', null, 'Bandra') as _post \gset

-- captain ~3km away (lng +0.03) discovers it within 10km, filtered to that mode
select tests.authenticate_as('cap@m.dev');
select is((select count(*)::int from public.discover_posts(19.07, 72.90, 10000, 'player_seeking_team') d where d.post_id = :'_post'::uuid), 1, 'captain discovers the nearby player post');
select ok((select approx_m from public.discover_posts(19.07, 72.90, 10000) d where d.post_id = :'_post'::uuid) between 2500 and 3800, 'distance ~3km');

-- captain opens a DM and both exchange messages
select public.get_or_create_dm_thread(tests.get_supabase_uid('player@m.dev')) as _t \gset
insert into public.dm_messages(thread_id, sender_id, body) values (:'_t'::uuid, tests.get_supabase_uid('cap@m.dev'), 'Want to play Sunday?');
select tests.authenticate_as('player@m.dev');
insert into public.dm_messages(thread_id, sender_id, body) values (:'_t'::uuid, tests.get_supabase_uid('player@m.dev'), 'Yes!');
select is((select count(*)::int from public.dm_messages where thread_id = :'_t'::uuid), 2, 'both messages stored in the thread');

-- player marks their post filled; it drops out of discovery
select public.mark_post_filled(:'_post'::uuid);
select is((select status::text from public.looking_for_posts where id = :'_post'::uuid), 'filled', 'post marked filled');
select tests.authenticate_as('cap@m.dev');
select is((select count(*)::int from public.discover_posts(19.07, 72.90, 10000) d where d.post_id = :'_post'::uuid), 0, 'filled post drops out of the feed');
select * from finish();
rollback;
