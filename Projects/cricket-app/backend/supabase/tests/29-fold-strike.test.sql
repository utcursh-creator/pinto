begin;
select plan(3);
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

-- single (swaps), dot (no), boundary 4 (no): after these the striker must be NS.
-- (striker_id stamped on rows is deliberately the opening striker each time; the fold must IGNORE it and derive strike.)
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1),
 (:'_in'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0),
 (:'_in'::uuid,3,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,4);
select is(public.compute_innings_state(:'_in'::uuid)->>'striker_id', (:'_ns'::uuid)::text, 'after single+dot+four, striker is NS (only the single swapped)');

-- complete the over with three more dots: at the 6th legal ball the over ends and strike swaps back to S.
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,4,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0),
 (:'_in'::uuid,5,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0),
 (:'_in'::uuid,6,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0);
select is(public.compute_innings_state(:'_in'::uuid)->>'striker_id', (:'_s'::uuid)::text, 'after the over completes, end-of-over swap puts S back on strike');
select is((public.compute_innings_state(:'_in'::uuid)->>'legal_balls')::int, 6, 'legal_balls = 6');
select * from finish();
rollback;
