begin;
select plan(12);
-- Sweep Unit A lifecycle roots: matches.status passes through innings_break
-- (SCOR-1 residue), start_innings validates squads/openers (SCOR-10/14),
-- POTM is frozen at result time (TOUR-8), fixtures get date/venue (TOUR-4).
select tests.create_supabase_user('lc@l.dev');
select tests.authenticate_as('lc@l.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('lc@l.dev'), 'Lc');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'a1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid, 'a2') as _a2 \gset
select public.add_guest_member(:'_b'::uuid, 'b1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid, 'b2') as _b2 \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 1) as _m \gset

-- start_innings validation
select throws_ok(
  format($$ select public.start_innings(%L, 1, %L, %L, %L, %L) $$,
    :'_m', :'_a', :'_b', :'_a1', :'_a1'),
  'P0001', 'the two openers must be different batters',
  'identical openers are rejected');

select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_a1'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_a2'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_b1'::uuid);
select throws_ok(
  format($$ select public.start_innings(%L, 1, %L, %L, %L, %L) $$,
    :'_m', :'_a', :'_b', :'_a1', :'_a2'),
  'P0001', 'both squads need at least 2 players',
  'a 1-player bowling squad is rejected once both sides declared');

select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_b2'::uuid);
select throws_ok(
  format($$ select public.start_innings(%L, 1, %L, %L, %L, %L) $$,
    :'_m', :'_a', :'_b', :'_a1', :'_b1'),
  'P0001', 'both openers must be in the batting squad',
  'an opener from the wrong side is rejected');

select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_a1'::uuid, :'_a2'::uuid) as _i1 \gset
select is((select status::text from public.matches where id = :'_m'::uuid), 'live',
  'starting the innings flips the match live');

-- innings break -> second innings -> live again
select public.record_ball(:'_i1'::uuid, :'_b1'::uuid, 1) from generate_series(1,6);
select public.mark_innings_break(:'_m'::uuid);
select is((select status::text from public.matches where id = :'_m'::uuid), 'innings_break',
  'mark_innings_break records the break');
select public.start_innings(:'_m'::uuid, 2, :'_b'::uuid, :'_a'::uuid, :'_b1'::uuid, :'_b2'::uuid, 7) as _i2 \gset
select is((select status::text from public.matches where id = :'_m'::uuid), 'live',
  'the chase flips the match back to live');

-- POTM freeze at result time
select public.record_ball(:'_i2'::uuid, :'_a1'::uuid, 6);
select public.record_ball(:'_i2'::uuid, :'_a1'::uuid, 1);
select public.set_match_result(:'_m'::uuid, 'win_by_wickets', :'_b'::uuid);
select isnt((select potm from public.matches where id = :'_m'::uuid), null,
  'the result persists a POTM on the match');
select is((select potm->>'member_id' from public.matches where id = :'_m'::uuid), :'_b1',
  'the chase hero on the winning side is the POTM');
select is(public.match_potm(:'_m'::uuid)->>'member_id', :'_b1',
  'match_potm serves the persisted pick');

-- schedule editing: allowed while unfinished, refused after
select public.create_match(:'_a'::uuid, :'_b'::uuid, 1) as _m2 \gset
select lives_ok(
  format($$ select public.update_match_schedule(%L, '2026-07-20 10:00+05:30', 'Shivaji Park') $$, :'_m2'),
  'the scorer can schedule an unfinished match');
select is((select venue from public.matches where id = :'_m2'::uuid), 'Shivaji Park',
  'venue lands on the match');
select throws_ok(
  format($$ select public.update_match_schedule(%L, null, 'Nowhere') $$, :'_m'),
  'P0001', 'this match already finished',
  'a finished match cannot be rescheduled');

select * from finish();
rollback;
