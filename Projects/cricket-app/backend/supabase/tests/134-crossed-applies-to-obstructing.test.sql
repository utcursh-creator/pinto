begin;
select plan(6);
-- Whole-system review #2 (2026-07-28), finding 80: the `crossed` flag is
-- collected for "obstructing the field" and then silently ignored.
--
-- The console shows "Batters had crossed" for obstructing exactly as it does
-- for a run out (_needsCrossedRuns covers both) and record_ball stores the
-- answer. But all three folds gate the crossing swap on
--
--   d.wicket_type = 'run_out' and coalesce(d.crossed, false)
--
-- while their own who-is-out line, twenty rows below, correctly reads
-- `wicket_type in ('run_out','obstructing')`. So for obstructing the swap never
-- happens: the surviving batter is left at the wrong end, the incoming batter
-- comes in at the wrong end, and because strike is derived cumulatively from
-- the opening pair, EVERY SUBSEQUENT BALL of the innings is credited to the
-- wrong batter. restamp_innings_strike then writes those wrong pairs onto every
-- stored delivery.
--
-- The scorer answered correctly and the app quietly threw the answer away.

select tests.create_supabase_user('cap@ob.dev');
select tests.authenticate_as('cap@ob.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@ob.dev'), 'Cap');
select public.create_team('Obs A', 'Pune') as _a \gset
select public.create_team('Obs B', 'Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid, 'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid, 'IN') as _in \gset
select public.add_guest_member(:'_b'::uuid, 'BW') as _bw \gset

-- CASE A: striker given out obstructing having completed 1 run, batters CROSSED.
-- Identical geometry to run-out case D in test 85: the incoming batter arrives
-- at the striker's end, the non-striker stays where they are.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m1 \gset
select public.start_innings(:'_m1'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i1 \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,wicket_type,dismissed_player_id,incoming_batter_id,crossed)
 values (:'_i1'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1,'obstructing',:'_s'::uuid,:'_in'::uuid,true);
set local role authenticated;

select is(public.compute_innings_state(:'_i1'::uuid)->>'striker_id', (:'_in'::uuid)::text,
  'obstructing + crossed puts the incoming batter on strike, exactly as a run out does');
select is(public.compute_innings_state(:'_i1'::uuid)->>'non_striker_id', (:'_ns'::uuid)::text,
  'and leaves the non-striker where they were');

-- CASE B: same ball, batters did NOT cross.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m2 \gset
select public.start_innings(:'_m2'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i2 \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,wicket_type,dismissed_player_id,incoming_batter_id,crossed)
 values (:'_i2'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1,'obstructing',:'_s'::uuid,:'_in'::uuid,false);
set local role authenticated;

select is(public.compute_innings_state(:'_i2'::uuid)->>'striker_id', (:'_ns'::uuid)::text,
  'not crossed: the odd run rotates strike to the non-striker');
select is(public.compute_innings_state(:'_i2'::uuid)->>'non_striker_id', (:'_in'::uuid)::text,
  'and the incoming batter takes the far end');

-- The three folds must move in LOCKSTEP. A fix to one of them that misses the
-- others leaves the scorecard and the stored deliveries disagreeing with the
-- live state - the exact class this codebase already has an invariant test for.
select public.restamp_innings_strike(:'_i1'::uuid);
select is(
  (select striker_id from public.deliveries where innings_id = :'_i1'::uuid and seq = 1),
  :'_s'::uuid, 'restamp leaves the dismissal ball itself alone');

-- and a following ball is stamped with the pair the state reports
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
 values (:'_i1'::uuid,2,:'_bw'::uuid,:'_in'::uuid,:'_ns'::uuid,0);
set local role authenticated;
select public.restamp_innings_strike(:'_i1'::uuid);
select is(
  (select striker_id from public.deliveries where innings_id = :'_i1'::uuid and seq = 2),
  :'_in'::uuid,
  'and restamp agrees with the fold on who faces the next ball - all three '
  'folds move together or the scorecard contradicts the live score');

select * from finish();
rollback;
