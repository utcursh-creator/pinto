begin;
select plan(7);
-- Unit 5 (penetration review 2026-07-07, completeness-critic findings):
-- a tied knockout must not brick the bracket, and one correction must not fan
-- out into a realtime message per delivery.

select tests.create_supabase_user('t5@t.dev');
select tests.authenticate_as('t5@t.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('t5@t.dev'), 'T5');
select public.create_team('T5 A', 'P') as _a \gset
select public.create_team('T5 B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'a1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid, 'a2') as _a2 \gset
select public.add_guest_member(:'_b'::uuid, 'b1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid, 'b2') as _b2 \gset

-- ---- 1. restamp must not rewrite rows whose pair did not change --------------
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_a1'::uuid, :'_a2'::uuid) as _i \gset
-- one full over from b1, then b2 (the consecutive-over guard is real)
select public.record_ball(:'_i'::uuid, :'_b1'::uuid, 0) from generate_series(1,6);
select public.record_ball(:'_i'::uuid, :'_b2'::uuid, 0) from generate_series(1,4);

-- updated_at only moves on a real write, so it is the witness for no-op writes
reset role;
update public.deliveries set updated_at = '2000-01-01' where innings_id = :'_i'::uuid;
select tests.authenticate_as('t5@t.dev');

select public.restamp_innings_strike(:'_i'::uuid);
select is(
  (select count(*)::int from public.deliveries
    where innings_id = :'_i'::uuid and updated_at = '2000-01-01'),
  10,
  'a restamp that changes nothing writes NO rows (was: one write + broadcast per ball)');

-- and it still re-stamps when the pair genuinely moves
reset role;
update public.deliveries set striker_id = :'_a2'::uuid
  where innings_id = :'_i'::uuid and seq = 5;
select tests.authenticate_as('t5@t.dev');
select public.restamp_innings_strike(:'_i'::uuid);
select is((select striker_id from public.deliveries where innings_id = :'_i'::uuid and seq = 5),
  :'_a1'::uuid,
  'a genuinely wrong pair is still corrected');

-- ---- 2. a TIED knockout must not brick the tournament ------------------------
select public.create_tournament('T5 Cup', 20, 2, 2) as _t \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _sf \gset
reset role;
insert into public.tournament_matches(match_id, tournament_id, stage, bracket_slot)
  values (:'_sf'::uuid, :'_t'::uuid, 'semifinal', 'SF1');
select tests.authenticate_as('t5@t.dev');

-- finish it as a TIE: complete, but with no winner
select public.set_match_result(:'_sf'::uuid, 'tie');
select is((select status::text from public.matches where id = :'_sf'::uuid), 'complete',
  'a tied semifinal is complete');
select is((select result->>'winner_team_id' from public.matches where id = :'_sf'::uuid), null,
  'and has no winner');

-- advance must NAME the tie, not claim the semis are unfinished
select throws_ok(
  format($$ select public.advance_playoffs(%L) $$, :'_t'),
  'P0001', 'SF1 finished level - record who won the super over to break the tie',
  'advance_playoffs explains the tie instead of lying about completeness');

-- the organizer can break it, and the tie stays on the record
select lives_ok(
  format($$ select public.resolve_tied_fixture(%L, %L, 'Super over') $$, :'_sf', :'_a'),
  'the organizer records the super-over winner');
select is(
  (select result->>'winner_team_id' from public.matches where id = :'_sf'::uuid),
  (:'_a')::text,
  'the progressing team is recorded');

select * from finish();
rollback;
