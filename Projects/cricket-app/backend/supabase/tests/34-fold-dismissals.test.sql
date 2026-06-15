begin;
select plan(5);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S') as _s \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid,'B3') as _b3 \gset
select public.add_guest_member(:'_a'::uuid,'B4') as _b4 \gset
select public.add_guest_member(:'_b'::uuid,'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

-- S bowled; B3 comes in and takes strike (bowled = striker out, incoming on strike)
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,incoming_batter_id) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,'bowled',:'_b3'::uuid);
select is((public.compute_innings_state(:'_in'::uuid)->>'wickets')::int, 1, 'one wicket');
select is(public.compute_innings_state(:'_in'::uuid)->>'striker_id', (:'_b3'::uuid)::text, 'incoming B3 on strike after bowled');
select is((public.compute_innings_state(:'_in'::uuid)->'bowling'->0->>'wickets')::int, 1, 'bowler credited the wicket');

-- run out of NS; B4 comes in. Run out is NOT credited to the bowler.
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,dismissed_player_id,incoming_batter_id) values
 (:'_in'::uuid,2,:'_bw'::uuid,:'_b3'::uuid,:'_ns'::uuid,'run_out',:'_ns'::uuid,:'_b4'::uuid);
select is((public.compute_innings_state(:'_in'::uuid)->>'wickets')::int, 2, 'two wickets');
select is((public.compute_innings_state(:'_in'::uuid)->'bowling'->0->>'wickets')::int, 1, 'run out NOT credited to the bowler');
select * from finish();
rollback;
