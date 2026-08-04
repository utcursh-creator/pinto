begin;
select plan(10);
-- Whole-system review #2 (2026-07-28), finding 56 plus the larger hole of the
-- same shape found while verifying it.
--
-- The scoring engine's guards live in the RPCs: the consecutive-over rule, the
-- bowler quota, which dismissals are legal off a wide or a no-ball, the
-- incoming-batter requirement, the expected_last_seq concurrency token, and the
-- three lockstep folds that must be re-run after every mutation. All of that is
-- decorative if the client can write the tables directly - and deliveries,
-- innings and match_squad each had an ALL-command policy for the scorer plus
-- the matching grants.
--
-- This is not "the scorer might cheat their own game". The rows are tournament
-- standings and OTHER PLAYERS' career records.
--
-- The controls matter as much as the blocks: the legitimate RPC path must keep
-- working, or this migration silently breaks scoring for everyone.

select tests.create_supabase_user('scorer@rw.dev');
select tests.create_supabase_user('rando@rw.dev');
select tests.authenticate_as('scorer@rw.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('scorer@rw.dev'), 'Scorer');
select public.create_team('RW A', 'Pune') as _a \gset
select public.create_team('RW B', 'Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')   as _s   \gset
select public.add_guest_member(:'_a'::uuid, 'NS')  as _ns  \gset
select public.add_guest_member(:'_b'::uuid, 'BW')  as _bw  \gset
select public.add_guest_member(:'_b'::uuid, 'BW2') as _bw2 \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset

-- 1. CONTROL first: the legitimate path must work, or everything below is
--    meaningless. add_squad_member and start_innings are SECURITY DEFINER.
select lives_ok(
  format($$ select public.add_squad_member(%L, %L, %L) $$, :'_m', :'_a', :'_s'),
  'the squad RPC still works');
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_ns'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_bw'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_bw2'::uuid);
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i \gset

-- 2. CONTROL: recording a ball through the RPC still works
select lives_ok(
  format($$ select public.record_ball(_innings_id => %L, _bowler_id => %L, _runs_off_bat => 1) $$,
         :'_i', :'_bw'),
  'record_ball still works');

-- 3-5. THE HOLE: the scorer must not be able to write deliveries directly.
--      Bypassing record_ball means bypassing every cricket-rule guard at once.
select throws_ok(
  format($$ insert into public.deliveries(innings_id, seq, bowler_id, striker_id,
              non_striker_id, runs_off_bat, wicket_type)
            values (%L, 999, %L, %L, %L, 0, 'bowled') $$,
         :'_i', :'_bw', :'_s', :'_ns'),
  '42501', null,
  'a scorer cannot insert a delivery directly (which would let them record a '
  'dismissal the Laws forbid, at any seq they like)');
-- seq, NOT is_legal: is_legal turns out to be GENERATED ALWAYS from the
-- extras columns, so the parser rejects any attempt to set it (428C9) long
-- before permissions are consulted - it was never tamperable, which is a nice
-- property of the schema and a bad assertion for this test. seq is an ordinary
-- column, and rewriting it is what desynchronises the three lockstep folds.
select throws_ok(
  format($$ update public.deliveries set seq = seq + 100 where innings_id = %L $$, :'_i'),
  '42501', null,
  'nor renumber deliveries and desynchronise the three lockstep folds');
select throws_ok(
  format($$ delete from public.deliveries where innings_id = %L $$, :'_i'),
  '42501', null,
  'nor delete a ball without the strike restamp');

-- 6-7. same for the innings and the squad
select throws_ok(
  format($$ update public.innings set target = 1 where id = %L $$, :'_i'),
  '42501', null,
  'a scorer cannot rewrite the innings row directly');
select throws_ok(
  format($$ delete from public.match_squad where match_id = %L $$, :'_m'),
  '42501', null,
  'nor remove a player from the squad behind the RPC''s back');

-- 8. FINDING 56: a tournament fixture cannot be deleted straight off the table.
--    delete_match refuses because it would corrupt the standings; the table
--    grant made that refusal decorative.
select throws_ok(
  format($$ delete from public.matches where id = %L $$, :'_m'),
  '42501', null,
  'matches cannot be deleted directly - delete_match''s tournament guard is '
  'the only door, so it can no longer be walked around');

-- 9. CONTROL: delete_match itself still deletes a casual match.
select lives_ok(
  format($$ select public.delete_match(%L) $$, :'_m'),
  'delete_match still works through the RPC');
select is(
  (select count(*)::int from public.matches where id = :'_m'::uuid),
  0, 'and the match really is gone');

select * from finish();
rollback;
