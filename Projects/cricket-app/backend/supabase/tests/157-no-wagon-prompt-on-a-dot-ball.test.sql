begin;
select plan(6);
-- Journey map C1: the scorer records ~120 deliveries standing at the boundary,
-- and the single most common outcome in gully cricket is a DOT BALL.
--
-- record_ball decides whether the console should ask where the ball went:
--   wagon_applicable := no wides/byes/leg-byes
--                   and (no noball secondary kind, or it was off the bat)
--                   and (no wicket, or caught/run_out)
-- It never asks whether any runs were actually SCORED. So a dot ball comes back
-- wagon_applicable = true and scoring_console_screen opens
-- "Where did 0 run(s) go?" on the most frequent event in the game.
--
-- The existing journeys hid this: their scoreRuns() helper dismisses a sheet
-- after EVERY run tap, so the suite worked around the defect instead of
-- reporting it. That is the whole reason this file exists.
--
-- A wagon entry means something for runs off the bat, and for a catch (where it
-- was caught). It means nothing for a ball that went nowhere.

select tests.create_supabase_user('wag@t.dev');
select tests.authenticate_as('wag@t.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('wag@t.dev'),'Cap');
select public.create_team('WA','P') as _a \gset
select public.create_team('WB','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S')   as _s   \gset
select public.add_guest_member(:'_a'::uuid,'NS')  as _ns  \gset
select public.add_guest_member(:'_b'::uuid,'BW')  as _bw  \gset
select public.add_guest_member(:'_b'::uuid,'BW2') as _bw2 \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m \gset
select public.add_squad_member(:'_m'::uuid,:'_a'::uuid,:'_s'::uuid,1,false,false);
select public.add_squad_member(:'_m'::uuid,:'_a'::uuid,:'_ns'::uuid,2,false,false);
select public.add_guest_member(:'_a'::uuid,'IN') as _in \gset
select public.add_squad_member(:'_m'::uuid,:'_a'::uuid,:'_in'::uuid,3,false,false);
select public.add_squad_member(:'_m'::uuid,:'_b'::uuid,:'_bw'::uuid,1,false,false);
select public.add_squad_member(:'_m'::uuid,:'_b'::uuid,:'_bw2'::uuid,2,false,false);
select public.start_innings(:'_m'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _i \gset

-- 1. THE DEFECT: a plain dot ball must not ask where the ball went
select is(
  (select wagon_applicable from public.record_ball(:'_i'::uuid, :'_bw'::uuid, 0)),
  false,
  'a DOT BALL does not prompt for a wagon-wheel placement - it is the most '
  'common outcome in the game and the ball went nowhere');

-- 2-3. CONTROLS: the cases where placement genuinely means something
select is(
  (select wagon_applicable from public.record_ball(:'_i'::uuid, :'_bw'::uuid, 4)),
  true, 'a boundary still prompts - that is what the wagon wheel is for');
select is(
  (select wagon_applicable from public.record_ball(:'_i'::uuid, :'_bw'::uuid, 1)),
  true, 'and a single still prompts');

-- 4. a dot that is also a WICKET (bowled) must not prompt either: nothing was
--    hit anywhere, and the batter is out.
select is(
  (select wagon_applicable from public.record_ball(
     :'_i'::uuid, :'_bw'::uuid, 0,
     _wicket_type => 'bowled'::public.wicket_type,
     _dismissed_player_id => :'_s'::uuid,
     _incoming_batter_id => :'_in'::uuid)),
  false, 'a batter bowled off a dot is not a shot to place on the field');

-- 5-6. extras are unchanged by this - they were already excluded
select is(
  (select wagon_applicable from public.record_ball(
     :'_i'::uuid, :'_bw'::uuid, 0, _extra_wides => 1)),
  false, 'a wide never prompted and still does not');
select is(
  (select (public.compute_innings_state(:'_i'::uuid)->>'runs')::int),
  6, 'CONTROL: the fold is untouched - 0 + 4 + 1 + 0(wicket) + 1(wide) = 6');

select * from finish();
rollback;
