begin;
select plan(5);
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

-- three legal singles (insert directly as scorer; the fold reads the log however it was written)
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1),
 (:'_in'::uuid,2,:'_bw'::uuid,:'_ns'::uuid,:'_s'::uuid,1),
 (:'_in'::uuid,3,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1);

select is((public.compute_innings_state(:'_in'::uuid)->>'runs')::int, 3, 'runs = 3');
select is((public.compute_innings_state(:'_in'::uuid)->>'wickets')::int, 0, 'wickets = 0');
select is((public.compute_innings_state(:'_in'::uuid)->>'legal_balls')::int, 3, 'legal_balls = 3');
select is(public.compute_innings_state(:'_in'::uuid)->>'over', '0.3', 'over = 0.3');
select is((public.compute_innings_state(:'_in'::uuid)->'extras'->>'wides')::int, 0, 'wides = 0');
select * from finish();
rollback;
