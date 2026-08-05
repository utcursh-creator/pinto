begin;
select plan(6);
-- Review #3 (MEDIUM): on every all-out innings the public scorecard marked the
-- LAST batter dismissed as not out.
--
-- The card put its not-out asterisk on whoever matched striker_id. That is not
-- "at the crease": record_ball permits a null incoming batter on the final
-- wicket - there is nobody left to come in - so the fold leaves the DISMISSED
-- batter sitting in _striker. The login-free /watch/<id> scorecard therefore
-- showed two not-out batters on an innings that lost every wicket, one of whom
-- the fall-of-wickets block right below named as dismissed.
--
-- The client now reads not-out as "at the crease AND not in fall_of_wickets".
-- That makes two fold contracts load-bearing for a PUBLIC record, and neither
-- was pinned by anything. This file pins them:
--
--   1. striker_id after the last wicket IS the dismissed batter (so the client
--      is right not to trust it), and
--   2. fall_of_wickets names every real dismissal and, critically, gives a
--      `retired_not_out` NO entry - otherwise a batter who retired hurt and
--      came back would be printed as out.

select tests.create_supabase_user('cap@fow.dev');
select tests.authenticate_as('cap@fow.dev');
insert into public.profiles(id, display_name)
  values (tests.get_supabase_uid('cap@fow.dev'), 'Cap');
select public.create_team('FOW A', 'Pune') as _a \gset
select public.create_team('FOW B', 'Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')   as _s   \gset
select public.add_guest_member(:'_a'::uuid, 'NS')  as _ns  \gset
select public.add_guest_member(:'_a'::uuid, 'IN')  as _in  \gset
select public.add_guest_member(:'_b'::uuid, 'BW')  as _bw  \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset

-- a REAL 3-player batting squad, so all_out = 2
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_s'::uuid,  1, false, false);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_ns'::uuid, 2, false, false);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_in'::uuid, 3, false, false);
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid,
       :'_s'::uuid, :'_ns'::uuid) as _i \gset

select current_role as _seedrole \gset
set local role postgres;
-- wicket 1: the striker is bowled, IN comes in
insert into public.deliveries(innings_id, seq, bowler_id, striker_id, non_striker_id,
       wicket_type, dismissed_player_id, incoming_batter_id)
values (:'_i'::uuid, 1, :'_bw'::uuid, :'_s'::uuid, :'_ns'::uuid,
        'bowled', :'_s'::uuid, :'_in'::uuid);
-- wicket 2: all out, so NO incoming batter - this is the case the card got wrong
insert into public.deliveries(innings_id, seq, bowler_id, striker_id, non_striker_id,
       wicket_type, dismissed_player_id)
values (:'_i'::uuid, 2, :'_bw'::uuid, :'_in'::uuid, :'_ns'::uuid,
        'bowled', :'_in'::uuid);
set local role :_seedrole;

select is(public.compute_innings_state(:'_i'::uuid)->>'innings_status', 'completed',
  'sanity: a 3-player squad is all out at 2 wickets');

-- 2. THE TRAP, pinned. If this ever stops being true the client is free to go
--    back to trusting striker_id - and until then it must not.
select is(
  public.compute_innings_state(:'_i'::uuid)->>'striker_id', :'_in',
  'after the last wicket the fold still names the DISMISSED batter as striker - '
  'there was no incoming batter to replace him, so striker_id is not "at the '
  'crease" and a scorecard must never read it as not out');

-- 3-4. fall_of_wickets is the truth the card now uses
select is(
  jsonb_array_length(public.compute_innings_state(:'_i'::uuid)->'fall_of_wickets'),
  2, 'both dismissals appear in fall_of_wickets');
select ok(
  (select bool_and(w->>'dismissed_player_id' is not null)
     from jsonb_array_elements(
       public.compute_innings_state(:'_i'::uuid)->'fall_of_wickets') w),
  'and every entry names WHO was out - the id the card matches on');

-- 5-6. A RETIRED NOT OUT must leave no trace in fall_of_wickets, or the card
--      would print a batter who walked off unhurt-and-returned as dismissed.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m2 \gset
select public.add_squad_member(:'_m2'::uuid, :'_a'::uuid, :'_s'::uuid,  1, false, false);
select public.add_squad_member(:'_m2'::uuid, :'_a'::uuid, :'_ns'::uuid, 2, false, false);
select public.add_squad_member(:'_m2'::uuid, :'_a'::uuid, :'_in'::uuid, 3, false, false);
select public.start_innings(:'_m2'::uuid, 1, :'_a'::uuid, :'_b'::uuid,
       :'_s'::uuid, :'_ns'::uuid) as _i2 \gset
select public.retire_batter(:'_i2'::uuid, :'_s'::uuid, false, :'_in'::uuid);

select is(
  jsonb_array_length(public.compute_innings_state(:'_i2'::uuid)->'fall_of_wickets'),
  0, 'a retired NOT OUT puts nothing in fall_of_wickets - he is not out, and '
     'the card reads exactly this list to decide who is');
select is(
  (public.compute_innings_state(:'_i2'::uuid)->>'wickets')::int,
  0, 'and counts no wicket');

select * from finish();
rollback;
