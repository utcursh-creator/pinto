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
select public.add_guest_member(:'_b'::uuid,'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

-- seq1: S scores 2 (stays on strike). seq2: S bowled (B3 in). seq3: B3 scores 3.
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,2);
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,incoming_batter_id) values
 (:'_in'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,'bowled',:'_b3'::uuid);
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,3,:'_bw'::uuid,:'_b3'::uuid,:'_ns'::uuid,3);

select is((select jsonb_array_length(public.compute_innings_state(:'_in'::uuid)->'partnerships')), 1, 'one completed partnership');
select is((public.compute_innings_state(:'_in'::uuid)->'partnerships'->0->>'runs')::int, 2, 'first partnership = 2 runs');
select is((public.compute_innings_state(:'_in'::uuid)->'partnerships'->0->>'a_runs')::int, 2, 'S contributed 2 to the first stand');
select is((public.compute_innings_state(:'_in'::uuid)->'current_partnership'->>'runs')::int, 3, 'current partnership = 3 runs');
select is((public.compute_innings_state(:'_in'::uuid)->'current_partnership'->>'b_runs')::int, 3, 'B3 contributed 3 to the current stand');
select * from finish();
rollback;
