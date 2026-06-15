begin;
select plan(4);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S') as _s \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid,'B3') as _b3 \gset
select public.add_guest_member(:'_b'::uuid,'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

-- Over 1: a four + 5 dots (4 runs, 0 wkts). Over 2: a six + a bowled + 4 dots (6 runs, 1 wkt).
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,4),
 (:'_in'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0),
 (:'_in'::uuid,3,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0),
 (:'_in'::uuid,4,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0),
 (:'_in'::uuid,5,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0),
 (:'_in'::uuid,6,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0);
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,7,:'_bw'::uuid,:'_ns'::uuid,:'_s'::uuid,6);
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,incoming_batter_id) values
 (:'_in'::uuid,8,:'_bw'::uuid,:'_ns'::uuid,:'_s'::uuid,'bowled',:'_b3'::uuid);
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,9,:'_bw'::uuid,:'_b3'::uuid,:'_s'::uuid,0),
 (:'_in'::uuid,10,:'_bw'::uuid,:'_b3'::uuid,:'_s'::uuid,0),
 (:'_in'::uuid,11,:'_bw'::uuid,:'_b3'::uuid,:'_s'::uuid,0),
 (:'_in'::uuid,12,:'_bw'::uuid,:'_b3'::uuid,:'_s'::uuid,0);

select is((select jsonb_array_length(public.compute_innings_state(:'_in'::uuid)->'per_over')), 2, 'two overs in Manhattan');
select is((public.compute_innings_state(:'_in'::uuid)->'per_over'->0->>'runs_in_over')::int, 4, 'over 1 = 4 runs');
select is((public.compute_innings_state(:'_in'::uuid)->'per_over'->1->>'wickets_in_over')::int, 1, 'over 2 = 1 wicket');
select is((public.compute_innings_state(:'_in'::uuid)->'worm'->1->>'cumulative_runs')::int, 10, 'worm after 2 overs = 10 cumulative');
select * from finish();
rollback;
