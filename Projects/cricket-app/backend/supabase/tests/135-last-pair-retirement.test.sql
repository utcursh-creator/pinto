begin;
select plan(6);
-- Whole-system review #2 (2026-07-28), finding 85: retire_batter accepts a
-- last-pair RETIRED HURT with no incoming batter, and the folds cannot
-- represent the result.
--
-- The guard is `if _incoming_batter_id is null and wickets_remaining >= 2 then
-- raise`, copied from record_ball. In record_ball that relaxation is safe
-- because the wicket ITSELF ends the innings. A retired-hurt counts no wicket,
-- so nothing ends: the fold sees wicket_type = 'retired_not_out' with a NULL
-- incoming batter, counts no wicket (so the all-out check never fires) and
-- leaves the pair untouched (so the retired batter stays on strike).
--
-- Every subsequent ball's runs, balls faced, fours and sixes are then credited
-- to somebody who has walked off - permanently, because career stats bake from
-- the cards.
--
-- The rule this pins: an incoming batter is required UNLESS the retirement is
-- itself the last wicket, which only a RETIRED OUT can be.

select tests.create_supabase_user('cap@lp.dev');
select tests.authenticate_as('cap@lp.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@lp.dev'), 'Cap');
select public.create_team('LP A', 'Pune') as _a \gset
select public.create_team('LP B', 'Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid, 'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid, 'IN') as _in \gset
select public.add_guest_member(:'_b'::uuid, 'BW') as _bw \gset

-- squad_size 2 makes all_out = 1, so the opening pair IS the last pair:
-- wickets_remaining = 1 from the first ball, which is the state the guard let
-- through.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20, 6, '{"squad_size":2}'::jsonb) as _m1 \gset
select public.start_innings(:'_m1'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i1 \gset

select is(
  (public.compute_innings_state(:'_i1'::uuid)->>'wickets_remaining')::int,
  1, 'the opening pair is the last pair');

-- 2. THE HOLE: a retired HURT with nobody coming in leaves a batter who has
--    walked off still on strike, and the innings never ends.
select throws_ok(
  format($$ select public.retire_batter(%L, %L, false, null) $$, :'_i1', :'_s'),
  'P0001', null,
  'a retired-hurt with no incoming batter is refused - it counts no wicket, so '
  'nothing would end the innings and the retired batter would keep facing');

-- 3. CONTROL: a RETIRED OUT with nobody coming in is legitimate at the last
--    wicket, because that retirement IS the wicket and it closes the innings.
--    Refusing this would strand the scorer with no way to record it at all.
select lives_ok(
  format($$ select public.retire_batter(%L, %L, true, null) $$, :'_i1', :'_s'),
  'a retired-OUT at the last wicket is still allowed - it ends the innings');
select is(
  (public.compute_innings_state(:'_i1'::uuid)->>'innings_status'),
  'completed', 'and the innings really does end');

-- 4. CONTROL: a retired hurt WITH a replacement is ordinary cricket and must
--    keep working.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20, 6, '{"squad_size":3}'::jsonb) as _m2 \gset
select public.start_innings(:'_m2'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i2 \gset
select lives_ok(
  format($$ select public.retire_batter(%L, %L, false, %L) $$, :'_i2', :'_s', :'_in'),
  'a retired-hurt with a replacement is unaffected');
select is(
  public.compute_innings_state(:'_i2'::uuid)->>'striker_id', (:'_in'::uuid)::text,
  'and the replacement actually takes the crease');

select * from finish();
rollback;
