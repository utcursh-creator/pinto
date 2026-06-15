begin;
select plan(5);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('Alpha','Pune') as _a \gset
select public.create_team('Beta','Pune') as _b \gset
-- players
select public.add_guest_member(:'_a'::uuid,'A_s') as _as \gset
select public.add_guest_member(:'_a'::uuid,'A_ns') as _ans \gset
select public.add_guest_member(:'_a'::uuid,'A_bowl') as _abowl \gset
select public.add_guest_member(:'_b'::uuid,'B_s') as _bs \gset
select public.add_guest_member(:'_b'::uuid,'B_ns') as _bns \gset
select public.add_guest_member(:'_b'::uuid,'B_bowl') as _bbowl \gset
-- 1-over-per-side match
select public.create_match(:'_a'::uuid,:'_b'::uuid,1) as _mt \gset

-- INNINGS 1: Alpha bats. 4,1,1,1,1,1 over six legal balls => 9, innings completes (overs done).
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_as'::uuid,:'_ans'::uuid) as _in1 \gset
select public.record_ball(:'_in1'::uuid, :'_bbowl'::uuid, 4);
select public.record_ball(:'_in1'::uuid, :'_bbowl'::uuid, 1);
select public.record_ball(:'_in1'::uuid, :'_bbowl'::uuid, 1);
select public.record_ball(:'_in1'::uuid, :'_bbowl'::uuid, 1);
select public.record_ball(:'_in1'::uuid, :'_bbowl'::uuid, 1);
select public.record_ball(:'_in1'::uuid, :'_bbowl'::uuid, 1);

select is((public.compute_innings_state(:'_in1'::uuid)->>'runs')::int, 9, 'innings 1 total = 9');
select is(public.compute_innings_state(:'_in1'::uuid)->>'innings_status', 'completed', 'innings 1 completes when the over is bowled');
-- integrity invariant: sum(batting runs) + extras == team total
select is(
  (select coalesce(sum((b->>'runs')::int),0)::int from jsonb_array_elements(public.compute_innings_state(:'_in1'::uuid)->'batting') b)
  + (public.compute_innings_state(:'_in1'::uuid)->'extras'->>'wides')::int
  + (public.compute_innings_state(:'_in1'::uuid)->'extras'->>'no_balls')::int
  + (public.compute_innings_state(:'_in1'::uuid)->'extras'->>'byes')::int
  + (public.compute_innings_state(:'_in1'::uuid)->'extras'->>'leg_byes')::int
  + (public.compute_innings_state(:'_in1'::uuid)->'extras'->>'penalty')::int,
  9, 'integrity: sum(batting runs) + extras == team total');

-- INNINGS 2: Beta chases target 10. Record a 6, a wrong 2 (undo it), then a 4 -> 10 reached -> win by wickets.
select public.start_innings(:'_mt'::uuid,2,:'_b'::uuid,:'_a'::uuid,:'_bs'::uuid,:'_bns'::uuid,10) as _in2 \gset
select public.record_ball(:'_in2'::uuid, :'_abowl'::uuid, 6);
select public.record_ball(:'_in2'::uuid, :'_abowl'::uuid, 2);
select public.undo_last_ball(:'_in2'::uuid);
select public.record_ball(:'_in2'::uuid, :'_abowl'::uuid, 4);

select is(public.compute_innings_state(:'_in2'::uuid)->'result'->>'result_type', 'win_by_wickets', 'chase won by wickets');
select is((public.compute_innings_state(:'_in2'::uuid)->'result'->>'balls_remaining')::int, 4, 'won with 4 balls to spare (the undone ball does not count)');
select * from finish();
rollback;
