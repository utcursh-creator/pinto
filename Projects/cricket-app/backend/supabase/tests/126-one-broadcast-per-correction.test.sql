begin;
select plan(6);
-- Whole-system review #2 (2026-07-28): a correction fans out one realtime
-- broadcast per shifted delivery.
--
-- insert_ball renumbers everything after the insertion point in two passes
-- (negate, restore) to dodge the unique index on (innings_id, seq), and the
-- AFTER ... FOR EACH ROW broadcast trigger fires on every single UPDATE.
-- Measured before the fix on this exact 30-ball fixture: 71 broadcasts for one
-- inserted ball, 15 for one deleted ball. An ordinary ball emits 1.
--
-- Each message makes every connected viewer re-fold the WHOLE innings, so one
-- tap of "insert the ball I missed" costs each watching phone hundreds of full
-- re-folds - and it scales with both innings length and audience size.
--
-- The renumbering is bookkeeping, not news. The viewer re-reads everything on
-- any message, so one message says exactly what the seventy-one said.

select tests.create_supabase_user('bcast@x.dev');
select tests.authenticate_as('bcast@x.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('bcast@x.dev'), 'BC');
select public.create_team('Bcast A','Pune') as _a \gset
select public.create_team('Bcast B','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S')   as _s   \gset
select public.add_guest_member(:'_a'::uuid,'NS')  as _ns  \gset
select public.add_guest_member(:'_b'::uuid,'BW')  as _bw  \gset
select public.add_guest_member(:'_b'::uuid,'BW2') as _bw2 \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m \gset
select public.start_innings(:'_m'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _i \gset

-- 30 deliveries, inserted directly so the fixture is cheap and deterministic
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
select :'_i'::uuid, g, :'_bw'::uuid, :'_s'::uuid, :'_ns'::uuid, 1
from generate_series(1,30) g;
set local role :_seedrole;

-- 1. CONTROL: ordinary scoring must keep emitting exactly one. If the fix
--    suppressed too broadly, live scoring would go silent - which is far worse
--    than being noisy, because the viewer would never learn anything at all.
select count(*) as _c1 from realtime.messages \gset
select public.record_ball(_innings_id => :'_i'::uuid, _bowler_id => :'_bw2'::uuid, _runs_off_bat => 1);
select is(
  (select count(*)::int - :_c1 from realtime.messages),
  1, 'an ordinary ball still broadcasts exactly once');

-- 2. THE BUG: inserting a ball early in the innings shifts 29 deliveries.
select count(*) as _c2 from realtime.messages \gset
select public.insert_ball(_innings_id => :'_i'::uuid, _after_seq => 2,
                          _bowler_id => :'_bw'::uuid, _runs_off_bat => 4) as _newid \gset
select is(
  (select count(*)::int - :_c2 from realtime.messages),
  1, 'inserting a ball mid-innings broadcasts ONCE, not once per shifted ball');

-- 3. the correction really did happen - a quiet no-op would also pass #2
select is(
  (select runs_off_bat from public.deliveries where innings_id = :'_i'::uuid and seq = 3),
  4, 'the inserted ball is really at seq 3');
select is(
  (select count(*)::int from public.deliveries where innings_id = :'_i'::uuid),
  32, 'and nothing was lost in the shuffle (30 + 1 scored + 1 inserted)');

-- 4. deleting shifts too
select count(*) as _c3 from realtime.messages \gset
select public.delete_ball(
  (select id from public.deliveries where innings_id = :'_i'::uuid and seq = 4));
select is(
  (select count(*)::int - :_c3 from realtime.messages),
  1, 'deleting a ball mid-innings broadcasts ONCE');
select is(
  (select count(*)::int from public.deliveries where innings_id = :'_i'::uuid),
  31, 'and the delete really landed');

select * from finish();
rollback;
