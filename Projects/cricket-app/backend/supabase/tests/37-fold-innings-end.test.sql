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
-- chasing innings: target 5
select public.start_innings(:'_mt'::uuid,2,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid,5) as _in \gset

-- 4 then 1 reaches the target (5) -> chase won. seq3 (a six) is AFTER the win -> orphaned, not scored.
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,4),
 (:'_in'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1),
 (:'_in'::uuid,3,:'_bw'::uuid,:'_ns'::uuid,:'_s'::uuid,6);
set local role :_seedrole;

select is((public.compute_innings_state(:'_in'::uuid)->>'runs')::int, 5, 'runs = 5 (the post-win six is orphaned, not scored)');
select is(public.compute_innings_state(:'_in'::uuid)->'result'->>'result_type', 'win_by_wickets', 'chase won by wickets');
select is((public.compute_innings_state(:'_in'::uuid)->'result'->>'margin_wickets')::int, 10, 'won by 10 wickets in hand');
select is(public.compute_innings_state(:'_in'::uuid)->>'innings_status', 'completed', 'innings completed on the chase');
select is((select jsonb_array_length(public.compute_innings_state(:'_in'::uuid)->'orphaned_deliveries')), 1, 'one orphaned delivery after the win');
select * from finish();
rollback;
