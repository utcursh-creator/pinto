begin;
select plan(2);
-- SCOR-2: a batter-removing wicket with no incoming batter is rejected unless it
-- is the last wicket. (3-player squad -> the first wicket is NOT the last.)
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@s.dev'), 'Cap');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid, 'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid, 'B3') as _b3 \gset
select public.add_guest_member(:'_b'::uuid, 'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _mt \gset
select public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_s'::uuid,  1, false, false);
select public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_ns'::uuid, 2, false, false);
select public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_b3'::uuid, 3, false, false);
select public.start_innings(:'_mt'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _in \gset

-- psql does not interpolate :'var' inside $$-quoting, which is why this used
-- unscoped subqueries. format()/%L is the correct way to get the captured ids in
-- (penetration review 2026-07-07) - the unscoped form addressed a stranger's
-- innings and threw 'not authorized' instead of the guard under test.
select throws_ok(
  format($$ select public.record_ball(
       _innings_id := %L, _bowler_id := %L,
       _wicket_type := 'bowled'::public.wicket_type,
       _dismissed_player_id := %L) $$, :'_in', :'_bw', :'_s'),
  'P0001', 'an incoming batter is required (this is not the last wicket)',
  'a non-final wicket with no incoming batter is rejected');

select lives_ok(
  format($$ select public.record_ball(
       _innings_id := %L, _bowler_id := %L,
       _wicket_type := 'bowled'::public.wicket_type,
       _dismissed_player_id := %L, _incoming_batter_id := %L) $$,
    :'_in', :'_bw', :'_s', :'_b3'),
  'the same wicket WITH an incoming batter is accepted');

select * from finish();
rollback;
