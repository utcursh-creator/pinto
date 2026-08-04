begin;
select plan(8);
-- Whole-system review #2 (2026-07-28), finding 72: byes and leg-byes off a
-- no-ball are bucketed as byes/leg-byes and not charged to the bowler.
--
-- Law 21.13: any runs completed off a No ball, together with its penalty, are
-- credited as NO BALL EXTRAS unless the ball was struck by the bat - in which
-- case they go to the striker. Either way the No ball is debited to the bowler.
-- Byes and leg-byes off a No ball do not exist under the current Laws.
--
-- The fold computed `_dconc := runs_off_bat + extra_wides +
-- extra_no_ball_penalty`, which is right for a legal delivery and understates
-- the bowler the moment extra_no_ball_penalty > 0; and it added extra_byes to
-- the byes bucket unconditionally, so the scorecard read "nb 1, b 2" - claiming
-- byes were scored off a delivery from which byes cannot be scored.
--
-- The innings TOTAL was never wrong. What was wrong is the bowler's figures and
-- the extras breakdown.
--
-- NOTE the console needs no change: its "The runs came from" question asks
-- whether the BAT was involved, which is exactly the distinction Law 21.13
-- turns on.

select tests.create_supabase_user('cap@nb.dev');
select tests.authenticate_as('cap@nb.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@nb.dev'), 'Cap');
select public.create_team('NB A', 'Pune') as _a \gset
select public.create_team('NB B', 'Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid, 'NS') as _ns \gset
select public.add_guest_member(:'_b'::uuid, 'BW') as _bw \gset

-- CASE A: no-ball, keeper misses, batters run 2.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m1 \gset
select public.start_innings(:'_m1'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i1 \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_no_ball_penalty,extra_byes,noball_secondary_kind)
 values (:'_i1'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1,2,'bye');
set local role authenticated;

select is(
  ((public.compute_innings_state(:'_i1'::uuid)->'bowling'->0->>'runs_conceded')::int),
  3, 'all three runs off the no-ball are debited to the bowler');
select is(
  ((public.compute_innings_state(:'_i1'::uuid)->'extras'->>'no_balls')::int),
  3, 'and they are reported as no-ball extras');
select is(
  ((public.compute_innings_state(:'_i1'::uuid)->'extras'->>'byes')::int),
  0, 'byes cannot be scored off a no-ball, so the byes bucket stays empty');
select is(
  ((public.compute_innings_state(:'_i1'::uuid)->>'runs')::int),
  3, 'the innings total is unchanged - it was never the wrong part');

-- CASE B: leg-byes off a no-ball behave identically
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m2 \gset
select public.start_innings(:'_m2'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i2 \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_no_ball_penalty,extra_leg_byes,noball_secondary_kind)
 values (:'_i2'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1,1,'leg_bye');
set local role authenticated;
select is(
  ((public.compute_innings_state(:'_i2'::uuid)->'bowling'->0->>'runs_conceded')::int),
  2, 'leg-byes off a no-ball are charged to the bowler too');
select is(
  ((public.compute_innings_state(:'_i2'::uuid)->'extras'->>'leg_byes')::int),
  0, 'and are not reported as leg-byes');

-- CASE C: CONTROL - byes off a LEGAL delivery are still byes, and still not
-- the bowler's fault. This is the half that was always right and must stay so.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m3 \gset
select public.start_innings(:'_m3'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i3 \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_byes)
 values (:'_i3'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,2);
set local role authenticated;
select is(
  ((public.compute_innings_state(:'_i3'::uuid)->'bowling'->0->>'runs_conceded')::int),
  0, 'byes off a LEGAL ball are still not charged to the bowler');
select is(
  ((public.compute_innings_state(:'_i3'::uuid)->'extras'->>'byes')::int),
  2, 'and are still reported as byes');

select * from finish();
rollback;
