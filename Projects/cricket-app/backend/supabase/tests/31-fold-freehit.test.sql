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

-- no-ball sets free hit
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_no_ball_penalty) values (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1);
select is(public.compute_innings_state(:'_in'::uuid)->>'free_hit_active','true','no-ball sets free hit');

-- a wide carries the free hit over (no consume)
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_wides) values (:'_in'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1);
select is(public.compute_innings_state(:'_in'::uuid)->>'free_hit_active','true','wide carries the free hit over');

-- a legal ball consumes the free hit
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values (:'_in'::uuid,3,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0);
select is(public.compute_innings_state(:'_in'::uuid)->>'free_hit_active','false','a legal ball consumes the free hit');

-- two no-balls in a row keep it set (chaining)
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_no_ball_penalty) values
 (:'_in'::uuid,4,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1),
 (:'_in'::uuid,5,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1);
select is(public.compute_innings_state(:'_in'::uuid)->>'free_hit_active','true','consecutive no-balls keep the free hit set');
select * from finish();
rollback;
