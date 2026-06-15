begin;
select plan(4);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S') as _s \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_b'::uuid,'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

-- record an over: single, dot, single, dot, single, dot (6 legal balls)
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 1);
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 0);
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 1);
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 0);
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 1);
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 0);
select is((public.compute_innings_state(:'_in'::uuid)->>'legal_balls')::int, 6, 'six legal balls after the over');

-- CASCADE: edit ball 1 from a single to a wide -> it is no longer a legal ball -> the over is now only 5 legal balls
select id as _d1 from public.deliveries where innings_id = :'_in'::uuid and seq = 1 \gset
select public.edit_ball(:'_d1'::uuid, 0, 1);
select is((public.compute_innings_state(:'_in'::uuid)->>'legal_balls')::int, 5, 'after editing ball 1 to a wide, the re-fold yields 5 legal balls');

-- undo the last ball
select public.undo_last_ball(:'_in'::uuid);
select is((select count(*)::int from public.deliveries where innings_id = :'_in'::uuid), 5, 'undo_last_ball removes the last delivery');

-- insert a missed ball after seq 2 (renumbers later deliveries)
select public.insert_ball(:'_in'::uuid, 2, :'_bw'::uuid, 0);
select is((select count(*)::int from public.deliveries where innings_id = :'_in'::uuid), 6, 'insert_ball adds a delivery (renumber)');
select * from finish();
rollback;
