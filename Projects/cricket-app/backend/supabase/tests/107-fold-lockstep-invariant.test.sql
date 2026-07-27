begin;
select plan(6);
-- HIGH (penetration review 2026-07-07, found independently by 4 fronts):
-- the three folds MUST agree ball-for-ball. compute_innings_state derives
-- squad_size from the real match_squad; compute_innings_cards and
-- restamp_innings_strike hardcoded 11. For any squad that is not 11 the folds
-- disagree about when the innings ended, so the SCORECARD silently drops or
-- keeps deliveries the score does not. matches.potm is frozen from cards at
-- result time and career stats bake from cards, so this corrupts real records
-- through a completely sanctioned path.
--
-- This is the invariant test that was missing: state and cards must agree.
select tests.create_supabase_user('ls@f.dev');
select tests.authenticate_as('ls@f.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('ls@f.dev'), 'Ls');
select public.create_team('Short A', 'P') as _a \gset
select public.create_team('Short B', 'P') as _b \gset
-- a TWO-player batting squad: all out at 1 wicket, not 10
select public.add_guest_member(:'_a'::uuid, 'a1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid, 'a2') as _a2 \gset
select public.add_guest_member(:'_b'::uuid, 'b1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid, 'b2') as _b2 \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_a1'::uuid, 1, false, false);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_a2'::uuid, 2, false, false);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_b1'::uuid, 1, false, false);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_b2'::uuid, 2, false, false);
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_a1'::uuid, :'_a2'::uuid) as _i \gset

-- 4 runs, then the ONLY wicket this squad can afford (all out at 1)
select public.record_ball(:'_i'::uuid, :'_b1'::uuid, 4);
select public.record_ball(:'_i'::uuid, :'_b1'::uuid, 0, _wicket_type := 'bowled',
       _dismissed_player_id := :'_a1'::uuid);

select is(public.compute_innings_state(:'_i'::uuid)->>'innings_status', 'completed',
  'a 2-player squad is all out after 1 wicket (state)');
select is(public.compute_innings_state(:'_i'::uuid)->>'runs', '4', 'state runs = 4');

-- balls recorded AFTER the innings ended are orphans: state ignores them and so
-- must cards. Before the fix, cards (all_out=10) counted them as live.
select public.record_ball(:'_i'::uuid, :'_b1'::uuid, 6);
select public.record_ball(:'_i'::uuid, :'_b1'::uuid, 6);

-- THE INVARIANT: the scorecard must reconstruct exactly the score.
select is(
  ((select coalesce(sum((e->>'runs')::int), 0)
     from jsonb_array_elements(public.compute_innings_cards(:'_i'::uuid)->'batting') e)
  + (select coalesce(sum((v)::int), 0) from jsonb_each_text(
       public.compute_innings_state(:'_i'::uuid)->'extras') as x(k, v)))::int,
  (public.compute_innings_state(:'_i'::uuid)->>'runs')::int,
  'LOCKSTEP: cards batting runs + extras == state runs');

select is(
  (select coalesce(sum((e->>'legal_balls')::int), 0)
     from jsonb_array_elements(public.compute_innings_cards(:'_i'::uuid)->'bowling') e)::int,
  (public.compute_innings_state(:'_i'::uuid)->>'legal_balls')::int,
  'LOCKSTEP: cards bowling legal_balls == state legal_balls');

select is(
  (select count(*)::int
     from jsonb_array_elements(public.compute_innings_cards(:'_i'::uuid)->'batting') e
    where (e->>'dismissed')::boolean),
  (public.compute_innings_state(:'_i'::uuid)->>'wickets')::int,
  'LOCKSTEP: cards dismissed count == state wickets');

-- restamp is the third fold: it must agree about where the innings ended, so
-- re-stamping leaves the pair at the moment of the last LIVE ball unchanged.
select striker_id as _pre from public.deliveries
  where innings_id = :'_i'::uuid and seq = 2 \gset
select public.restamp_innings_strike(:'_i'::uuid);
select is((select striker_id from public.deliveries where innings_id = :'_i'::uuid and seq = 2),
  :'_pre'::uuid,
  'LOCKSTEP: restamp agrees with the fold about the live pair');

select * from finish();
rollback;
