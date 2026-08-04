begin;
select plan(10);
-- Whole-system review #2 (2026-07-28): the scoring console can only attach a
-- wicket to a LEGAL delivery, so a stumping off a wide and a run-out off a
-- no-ball - both routine, and the stumping-off-a-wide is a T20 staple - cannot
-- be recorded at all. The scorer's only option is to log it as an ordinary
-- run-out, which silently corrupts the innings twice over: the extra run is
-- lost AND a legal ball is consumed, so the over ends one delivery early and
-- every subsequent over is misattributed.
--
-- record_ball ALREADY validates the Laws correctly (guards below, assertions
-- 9-10). This test pins the other half: that the FOLD counts these deliveries
-- properly, so the client fix has something correct to talk to. A guard that
-- lets a ball through proves nothing about how the ball is then counted.

select tests.create_supabase_user('cap@w.dev');
select tests.authenticate_as('cap@w.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@w.dev'), 'Cap');
select public.create_team('Wides XI', 'Pune') as _a \gset
select public.create_team('Foes', 'Pune')     as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')   as _s   \gset
select public.add_guest_member(:'_a'::uuid, 'NS')  as _ns  \gset
select public.add_guest_member(:'_a'::uuid, 'IN')  as _in  \gset
select public.add_guest_member(:'_a'::uuid, 'IN2') as _in2 \gset
select public.add_guest_member(:'_a'::uuid, 'IN3') as _in3 \gset
select public.add_guest_member(:'_b'::uuid, 'Bowl') as _bw \gset

select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i \gset

-- 1. STUMPED OFF A WIDE. The keeper collects a wide down the leg side and
--    whips the bails off. Utterly ordinary; today it is unrecordable.
select lives_ok(
  format($$ select public.record_ball(
      _innings_id => %L, _bowler_id => %L, _extra_wides => 1,
      _wicket_type => 'stumped', _dismissed_player_id => %L,
      _incoming_batter_id => %L, _fielder_id => %L) $$,
    :'_i', :'_bw', :'_s', :'_in', :'_bw'),
  'a batter can be stumped off a wide');

-- 2-4. and it is counted as a wide, not as a legal ball
select is((public.compute_innings_state(:'_i'::uuid)->>'legal_balls')::int, 0,
  'the wide does not consume a legal ball - the over is still six to come');
select is((public.compute_innings_state(:'_i'::uuid)->>'runs')::int, 1,
  'the wide still scores its run');
select is((public.compute_innings_state(:'_i'::uuid)->>'wickets')::int, 1,
  'and the wicket still falls');

-- 5. RUN OUT OFF A NO-BALL, with a run completed before the throw came in.
select lives_ok(
  format($$ select public.record_ball(
      _innings_id => %L, _bowler_id => %L, _extra_no_ball_penalty => 1,
      _runs_off_bat => 1, _noball_secondary_kind => 'off_bat',
      _wicket_type => 'run_out', _dismissed_player_id => %L,
      _incoming_batter_id => %L, _crossed => false) $$,
    :'_i', :'_bw', :'_in', :'_in2'),
  'a batter can be run out off a no-ball');

-- 6-8. the no-ball is a no-ball: no legal ball, penalty + the run off the bat
select is((public.compute_innings_state(:'_i'::uuid)->>'legal_balls')::int, 0,
  'the no-ball does not consume a legal ball either');
select is((public.compute_innings_state(:'_i'::uuid)->>'runs')::int, 3,
  'wide 1 + no-ball 1 + the single run off the bat = 3');
select is((public.compute_innings_state(:'_i'::uuid)->>'wickets')::int, 2,
  'both wickets stand');

-- 9-10. and the Laws still bind - these dismissals are NOT available
select throws_ok(
  format($$ select public.record_ball(
      _innings_id => %L, _bowler_id => %L, _extra_wides => 1,
      _wicket_type => 'bowled', _dismissed_player_id => %L,
      _incoming_batter_id => %L) $$,
    :'_i', :'_bw', :'_ns', :'_in3'),
  'P0001', null,
  'you cannot be bowled off a wide');
select throws_ok(
  format($$ select public.record_ball(
      _innings_id => %L, _bowler_id => %L, _extra_no_ball_penalty => 1,
      _wicket_type => 'stumped', _dismissed_player_id => %L,
      _incoming_batter_id => %L, _fielder_id => %L) $$,
    :'_i', :'_bw', :'_ns', :'_in3', :'_bw'),
  'P0001', null,
  'you cannot be stumped off a no-ball');

select * from finish();
rollback;
