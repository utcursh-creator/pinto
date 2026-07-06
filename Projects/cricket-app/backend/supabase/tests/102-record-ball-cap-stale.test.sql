begin;
select plan(7);
-- SCOR-15 + SCOR-24: the bowler over-cap (rules.max_overs_per_bowler) and the
-- optimistic-concurrency fence (_expected_last_seq) on record_ball.
select tests.create_supabase_user('cap@c.dev');
select tests.authenticate_as('cap@c.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@c.dev'), 'Cap');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'a1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid, 'a2') as _a2 \gset
select public.add_guest_member(:'_b'::uuid, 'b1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid, 'b2') as _b2 \gset
select public.add_guest_member(:'_b'::uuid, 'b3') as _b3 \gset
-- 6-over match, 1 over per bowler (the rule the app stamps at creation)
select public.create_match(:'_a'::uuid, :'_b'::uuid, 6, 6,
  '{"max_overs_per_bowler": 1}'::jsonb) as _m \gset
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_a1'::uuid, :'_a2'::uuid) as _i \gset

-- b1 bowls a full over (6 legal balls incl. one that followed a wide)
select public.record_ball(:'_i'::uuid, :'_b1'::uuid, 0) from generate_series(1,3);
select public.record_ball(:'_i'::uuid, :'_b1'::uuid, 0, 1);  -- wide, not a ball
select public.record_ball(:'_i'::uuid, :'_b1'::uuid, 0) from generate_series(1,3);
select is(public.compute_innings_state(:'_i'::uuid)->>'over', '1.0', 'over 1 complete');

-- b2 bowls over 2; b1 at the cap cannot start over 3
select public.record_ball(:'_i'::uuid, :'_b2'::uuid, 0) from generate_series(1,6);
select throws_ok(
  format($$ select public.record_ball(%L, %L, 1) $$, :'_i', :'_b1'),
  'P0001', 'bowler has reached the 1 over limit',
  'a bowler at the cap cannot start another over');
select lives_ok(
  format($$ select public.record_ball(%L, %L, 1) $$, :'_i', :'_b3'),
  'a fresh bowler starts over 3');

-- mid-over the cap never fires (only over starts are gated)
select lives_ok(
  format($$ select public.record_ball(%L, %L, 1) $$, :'_i', :'_b3'),
  'the same bowler continues mid-over');

-- SCOR-24: stale fence (7 rows in over 1 incl. the wide + 6 in over 2 + 2 by b3)
select is(public.compute_innings_state(:'_i'::uuid)->>'last_seq', '15', 'fold reports last_seq');
select throws_ok(
  format($$ select public.record_ball(%L, %L, 1, _expected_last_seq := 3) $$, :'_i', :'_b3'),
  'P0001', 'the innings changed on another device - refresh before recording',
  'an append computed against a stale state is rejected');
select lives_ok(
  format($$ select public.record_ball(%L, %L, 1, _expected_last_seq := 15) $$, :'_i', :'_b3'),
  'an append with the current version token succeeds');

select * from finish();
rollback;
