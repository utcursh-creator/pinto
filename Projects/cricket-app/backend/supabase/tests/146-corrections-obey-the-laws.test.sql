begin;
select plan(12);
-- Review #2 finding 28, REOPENED by review #3 and confirmed by hand on the live
-- database: edit_ball and insert_ball accept dismissals that cannot happen.
--
-- record_ball has enforced the Laws since the beginning:
--     off a no-ball or a free hit, only run out / obstructing / hit ball twice
--     off a wide,        only hit wicket / obstructing / run out / stumped
-- and the scoring console mirrors the same lists in its wicket sheet. The two
-- CORRECTION paths never had them. I refuted finding 28 in the review-#2 ledger
-- on the grounds that "record_ball ALREADY validates both guards correctly" -
-- true, and beside the point, because the finding was about correcting a ball,
-- not recording one. That refutation is withdrawn here.
--
-- What it costs: a scorer fixing "that was actually a no-ball" on a wicket ball
-- produces a batter bowled off a no-ball. compute_innings_cards feeds
-- player_career_stats, compute_match_potm (frozen into matches.potm) and
-- tournament_leaderboard, so the impossible wicket becomes a permanent public
-- career record for a bowler who never took it.

select tests.create_supabase_user('cap@law.dev');
select tests.authenticate_as('cap@law.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@law.dev'),'Cap');
select public.create_team('Law A','Pune') as _a \gset
select public.create_team('Law B','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S')   as _s  \gset
select public.add_guest_member(:'_a'::uuid,'NS')  as _ns \gset
select public.add_guest_member(:'_a'::uuid,'IN')  as _in \gset
select public.add_guest_member(:'_b'::uuid,'BW')  as _bw \gset
select public.add_guest_member(:'_b'::uuid,'FLD') as _f  \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m \gset
select public.start_innings(:'_m'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _i \gset

-- three legal dot balls to correct
select delivery_id as _d1 from public.record_ball(:'_i'::uuid, :'_bw'::uuid, 0) \gset
select delivery_id as _d2 from public.record_ball(:'_i'::uuid, :'_bw'::uuid, 0) \gset
select delivery_id as _d3 from public.record_ball(:'_i'::uuid, :'_bw'::uuid, 0) \gset
select delivery_id as _d4 from public.record_ball(:'_i'::uuid, :'_bw'::uuid, 0) \gset

-- ============ edit_ball ============
-- 1. bowled off a no-ball. THE bug, reproduced by hand on 2026-08-05: this was
--    accepted and the fold reported wickets=1, runs=1, legal_balls=0.
select throws_ok(
  format($$ select public.edit_ball(%L, _extra_no_ball_penalty => 1,
              _wicket_type => 'bowled', _dismissed_player_id => %L,
              _incoming_batter_id => %L) $$, :'_d1', :'_s', :'_in'),
  'P0001', 'illegal dismissal on a no-ball/free-hit',
  'edit_ball refuses a batter bowled off a no-ball');

-- 2. caught off a wide - the other half of the same hole
select throws_ok(
  format($$ select public.edit_ball(%L, _extra_wides => 1,
              _wicket_type => 'caught', _dismissed_player_id => %L,
              _fielder_id => %L, _incoming_batter_id => %L) $$,
          :'_d1', :'_s', :'_f', :'_in'),
  'P0001', 'illegal dismissal on a wide',
  'edit_ball refuses a catch off a wide');

-- 3-4. CONTROLS: the dismissals that ARE possible must still be accepted, or
--      the guard has simply broken the correction path instead of fixing it.
select lives_ok(
  format($$ select public.edit_ball(%L, _extra_no_ball_penalty => 1,
              _wicket_type => 'run_out', _dismissed_player_id => %L,
              _incoming_batter_id => %L, _crossed => false) $$,
          :'_d1', :'_s', :'_in'),
  'a run out off a no-ball is legal and still goes through');
-- NOT _d2: test 3 just turned _d1 into a no-ball, which makes _d2 a FREE HIT,
-- and a stumping off a free hit is impossible. The guard refusing it there is
-- correct - a good sign that it agrees with the fold about which ball is which.
select lives_ok(
  format($$ select public.edit_ball(%L, _extra_wides => 1,
              _wicket_type => 'stumped', _dismissed_player_id => %L,
              _incoming_batter_id => %L) $$, :'_d3', :'_s', :'_in'),
  'and a stumping off a wide');

-- 5. and an ordinary legal wicket is untouched by any of this
select lives_ok(
  format($$ select public.edit_ball(%L, _wicket_type => 'bowled',
              _dismissed_player_id => %L, _incoming_batter_id => %L) $$,
          :'_d4', :'_s', :'_in'),
  'a plain bowled on a legal delivery is still allowed');

-- ============ insert_ball ============
select public.start_innings(:'_m'::uuid,2,:'_b'::uuid,:'_a'::uuid,:'_bw'::uuid,:'_f'::uuid) as _i2 \gset
select delivery_id from public.record_ball(:'_i2'::uuid, :'_s'::uuid, 0) \gset

-- 6-7. the same two impossibilities, on the insert path
select throws_ok(
  format($$ select public.insert_ball(%L, 1, %L, 0, 0, 1, 0, 0, 0, null,
              'bowled', %L, %L) $$, :'_i2', :'_s', :'_bw', :'_f'),
  'P0001', 'illegal dismissal on a no-ball/free-hit',
  'insert_ball refuses a batter bowled off a no-ball');
select throws_ok(
  format($$ select public.insert_ball(%L, 1, %L, 0, 1, 0, 0, 0, 0, null,
              'caught', %L, %L, %L) $$, :'_i2', :'_s', :'_bw', :'_f', :'_f'),
  'P0001', 'illegal dismissal on a wide',
  'insert_ball refuses a catch off a wide');

-- 8-9. CONTROLS on the insert path too
select lives_ok(
  format($$ select public.insert_ball(%L, 1, %L, 0, 0, 1, 0, 0, 0, null,
              'run_out', %L, %L) $$, :'_i2', :'_s', :'_bw', :'_f'),
  'a run out off an inserted no-ball is legal');
select lives_ok(
  format($$ select public.insert_ball(%L, 1, %L, 0, 1, 0, 0, 0, 0, null,
              'stumped', %L, %L) $$, :'_i2', :'_s', :'_bw', :'_f'),
  'and a stumping off an inserted wide');

-- ============ the FREE HIT, which is the half a naive fix forgets ============
-- The delivery after a no-ball is a free hit, and off a free hit only the same
-- three dismissals are possible - even though THAT delivery is a legal ball with
-- no no-ball penalty of its own. The fold decides it by looking back at the last
-- delivery that was either a no-ball or legal; the guard has to agree with the
-- fold or the two disagree about the same ball.
-- a SECOND match: a match only has two innings, so the free-hit fixture cannot
-- borrow a third from the one above
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m2 \gset
select public.start_innings(:'_m2'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _i3 \gset
-- a no-ball, then the free hit it creates.
-- (NOTE: nothing may follow \gset on its line - psql reads the rest as the
-- variable-name PREFIX, so a trailing comment silently leaves the variable
-- unset and the next :'var' fails with a bare syntax error.)
select delivery_id as _nb from public.record_ball(:'_i3'::uuid, :'_bw'::uuid, 0, 0, 1) \gset
select delivery_id as _fh from public.record_ball(:'_i3'::uuid, :'_bw'::uuid, 1) \gset
select is(
  (public.compute_innings_state(:'_i3'::uuid)->>'free_hit_active')::boolean, false,
  'sanity: the free hit has been used up by that legal ball');

-- 11. correcting the free-hit ball into a bowled must be refused
select throws_ok(
  format($$ select public.edit_ball(%L, _wicket_type => 'bowled',
              _dismissed_player_id => %L, _incoming_batter_id => %L) $$,
          :'_fh', :'_s', :'_in'),
  'P0001', 'illegal dismissal on a no-ball/free-hit',
  'a batter cannot be bowled off a free hit, even though the ball itself is '
  'legal - the guard has to look back at the previous delivery, exactly as the '
  'fold does');

-- 12. CONTROL: run out off a free hit is legal
select lives_ok(
  format($$ select public.edit_ball(%L, _wicket_type => 'run_out',
              _dismissed_player_id => %L, _incoming_batter_id => %L,
              _crossed => false) $$, :'_fh', :'_s', :'_in'),
  'but a run out off a free hit is');

select * from finish();
rollback;
