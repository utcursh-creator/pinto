begin;
select plan(6);
-- Review #3 (MEDIUM), finding 15: no correction path can set the run-out
-- `crossed` flag, so a corrected run-out leaves the WRONG batter on strike for
-- the rest of the innings.
--
-- A ball goes unrecorded (scorer distracted between overs). On it the
-- non-striker was run out and the batters HAD crossed. The scorer inserts it
-- from the ball log - and insert_ball's signature has no _crossed at all, so
-- the row is written with crossed = NULL. All three folds test
-- `coalesce(d.crossed,false)`, so they skip the crossing swap; every later run,
-- ball faced, four and six is credited to the wrong batter, and
-- restamp_innings_strike stamps the wrong striker onto every subsequent row of
-- the ball log.
--
-- edit_ball ALREADY takes _crossed (it was given one when review #2 stopped it
-- DESTROYING an existing value). insert_ball is the hole.
--
-- THE ASSERTION IS LOCKSTEP, not a hand-derived expectation: the correction
-- path must land in the same place as the live path. If insert_ball with
-- _crossed => true does not agree with record_ball with _crossed => true, one
-- of them is wrong, and no re-derivation of the Laws in this file could tell
-- you which.

select tests.create_supabase_user('cap@cx.dev');
select tests.authenticate_as('cap@cx.dev');
insert into public.profiles(id, display_name)
  values (tests.get_supabase_uid('cap@cx.dev'), 'Cap');
select public.create_team('CX A', 'Pune') as _a \gset
select public.create_team('CX B', 'Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid, 'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid, 'IN') as _in \gset
select public.add_guest_member(:'_a'::uuid, 'X4') as _x4 \gset
select public.add_guest_member(:'_b'::uuid, 'BW') as _bw \gset

-- TWO identical innings. One is scored live, one is corrected into existence.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m1 \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m2 \gset
select public.add_squad_member(:'_m1'::uuid, :'_a'::uuid, :'_s'::uuid,  1, false, false);
select public.add_squad_member(:'_m1'::uuid, :'_a'::uuid, :'_ns'::uuid, 2, false, false);
select public.add_squad_member(:'_m1'::uuid, :'_a'::uuid, :'_in'::uuid, 3, false, false);
select public.add_squad_member(:'_m1'::uuid, :'_a'::uuid, :'_x4'::uuid, 4, false, false);
select public.add_squad_member(:'_m2'::uuid, :'_a'::uuid, :'_s'::uuid,  1, false, false);
select public.add_squad_member(:'_m2'::uuid, :'_a'::uuid, :'_ns'::uuid, 2, false, false);
select public.add_squad_member(:'_m2'::uuid, :'_a'::uuid, :'_in'::uuid, 3, false, false);
select public.add_squad_member(:'_m2'::uuid, :'_a'::uuid, :'_x4'::uuid, 4, false, false);
select public.start_innings(:'_m1'::uuid, 1, :'_a'::uuid, :'_b'::uuid,
       :'_s'::uuid, :'_ns'::uuid) as _i1 \gset
select public.start_innings(:'_m2'::uuid, 1, :'_a'::uuid, :'_b'::uuid,
       :'_s'::uuid, :'_ns'::uuid) as _i2 \gset

-- THE LIVE PATH: the non-striker is run out for a single, and they HAD crossed.
select public.record_ball(
  _innings_id => :'_i1'::uuid,
  _bowler_id => :'_bw'::uuid,
  _runs_off_bat => 1,
  _wicket_type => 'run_out'::public.wicket_type,
  _dismissed_player_id => :'_ns'::uuid,
  _incoming_batter_id => :'_in'::uuid,
  _crossed => true);

-- THE CORRECTION PATH: the same ball, inserted from the ball log.
select public.insert_ball(
  _innings_id => :'_i2'::uuid,
  _after_seq => 0,
  _bowler_id => :'_bw'::uuid,
  _runs_off_bat => 1,
  _wicket_type => 'run_out'::public.wicket_type,
  _dismissed_player_id => :'_ns'::uuid,
  _incoming_batter_id => :'_in'::uuid,
  _crossed => true) as _ins \gset

select is(
  (select crossed from public.deliveries where id = :'_ins'::uuid),
  true, 'the inserted ball actually stores crossed - it was NULL before, and '
        'every fold reads coalesce(crossed,false), so NULL silently means "did '
        'not cross"');

select is(
  public.compute_innings_state(:'_i2'::uuid)->>'striker_id',
  public.compute_innings_state(:'_i1'::uuid)->>'striker_id',
  'the CORRECTED innings puts the same batter on strike as the LIVE one');
select is(
  public.compute_innings_state(:'_i2'::uuid)->>'non_striker_id',
  public.compute_innings_state(:'_i1'::uuid)->>'non_striker_id',
  'and the same batter at the other end');

-- 4. restamp_innings_strike is what writes the pair onto every LATER row of the
--    ball log, so a wrong flag here does not just mis-credit runs - it rewrites
--    history the scorer reads back.
select is(
  (select striker_id from public.deliveries where innings_id = :'_i2'::uuid
    order by seq desc limit 1),
  (select striker_id from public.deliveries where innings_id = :'_i1'::uuid
    order by seq desc limit 1),
  'and the stamped ball-log rows agree too');

-- 5-6. The flag must also be CORRECTABLE in both directions. edit_ball is a
--      COALESCE patch, so "leave alone" is null - a client that means false has
--      to say false, which is exactly what a switch does.
select public.edit_ball(_delivery_id => :'_ins'::uuid, _crossed => false);
select is(
  (select crossed from public.deliveries where id = :'_ins'::uuid),
  false, 'a run-out recorded with the switch the wrong way can be corrected '
         'back - patching to false is not the same as patching to null');
select isnt(
  public.compute_innings_state(:'_i2'::uuid)->>'striker_id',
  public.compute_innings_state(:'_i1'::uuid)->>'striker_id',
  'and the derived strike follows the correction - if this matched, the edit '
  'would have changed a stored column that no fold reads');

select * from finish();
rollback;
