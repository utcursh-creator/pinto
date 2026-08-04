begin;
select plan(4);
-- Whole-system review #2 (2026-07-28), finding 67: tournament_standings
-- computes NRR overs with a hardcoded /6.0, ignoring matches.balls_per_over.
--
-- NRR is the tiebreaker that decides WHO QUALIFIES from a group. With 8-ball
-- overs the divisor is wrong by a third, so a side's run rate is overstated by
-- the same third - and both the run rate FOR and AGAINST move, so the error
-- does not cancel. Two teams level on points can swap places, and
-- generate_playoffs seeds the semifinals from exactly this order.
--
-- The app supports other over lengths: matches.balls_per_over is a real column,
-- create_match takes it, and pgTAP 81 already covers a non-6 fold. So this is
-- not a hypothetical setting.
--
-- Fixture: one completed group match at 8 balls per over, squad_size 2 so a
-- single wicket is all out and the totals stay hand-computable.

select tests.create_supabase_user('org@nrr.dev');
select tests.authenticate_as('org@nrr.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('org@nrr.dev'),'Org');
select public.create_tournament('Eight Ball Cup', 10, 1, 2) as _t \gset
select public.create_team('P','C') as _p \gset
select public.create_team('Q','C') as _q \gset
select public.add_guest_member(:'_p'::uuid,'p1') as _p1 \gset
select public.add_guest_member(:'_p'::uuid,'p2') as _p2 \gset
select public.add_guest_member(:'_p'::uuid,'pb') as _pb \gset
select public.add_guest_member(:'_q'::uuid,'q1') as _q1 \gset
select public.add_guest_member(:'_q'::uuid,'q2') as _q2 \gset
select public.add_guest_member(:'_q'::uuid,'qb') as _qb \gset
select public.add_tournament_team(:'_t'::uuid, :'_p'::uuid, 'A');
select public.add_tournament_team(:'_t'::uuid, :'_q'::uuid, 'A');

-- 10 overs of EIGHT balls = 80 legal balls.
select public.create_match(:'_p'::uuid,:'_q'::uuid,10,8,'{"squad_size":2}'::jsonb) as _m \gset
select public.start_innings(:'_m'::uuid,1,:'_p'::uuid,:'_q'::uuid,:'_p1'::uuid,:'_p2'::uuid) as _i1 \gset
select current_role as _seedrole \gset
set local role postgres;
-- P: 80 runs off 40 legal balls, not all out -> 40/8 = 5.0 overs faced,
-- so 16.00 rpo. Under the hardcoded /6 it reads 40/6 = 6.667 overs -> 12.00.
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
select :'_i1'::uuid, g, :'_qb'::uuid, :'_p1'::uuid, :'_p2'::uuid, 2
from generate_series(1,40) g;
set local role :_seedrole;

select public.start_innings(:'_m'::uuid,2,:'_q'::uuid,:'_p'::uuid,:'_q1'::uuid,:'_q2'::uuid) as _i2 \gset
set local role postgres;
-- Q: 40 runs off 40 legal balls, not all out -> 5.0 overs -> 8.00 rpo.
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
select :'_i2'::uuid, g, :'_pb'::uuid, :'_q1'::uuid, :'_q2'::uuid, 1
from generate_series(1,40) g;
set local role :_seedrole;
select public.set_match_result(:'_m'::uuid, 'win_by_runs', :'_p'::uuid);
-- link it into the group, the way generate_group_fixtures would
set local role postgres;
insert into public.tournament_matches(match_id,tournament_id,stage,group_label)
values (:'_m'::uuid, :'_t'::uuid, 'group', 'A');
set local role :_seedrole;

-- 1-2. P scored at 16.00 and conceded at 8.00 -> NRR +8.000
select is(
  (select (r->>'nrr')::numeric
     from jsonb_array_elements(public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') r
    where r->>'team_id' = :'_p'),
  8.000,
  'NRR uses the match''s OWN over length: 40 balls at 8 per over is 5 overs, '
  'not 6.667. With the hardcoded /6 it read +6.000 (12.00 - 6.00 instead '
  'of 16.00 - 8.00), and NRR decides who qualifies from a group');
select is(
  (select (r->>'nrr')::numeric
     from jsonb_array_elements(public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') r
    where r->>'team_id' = :'_q'),
  -8.000, 'and the opponent''s is its exact mirror');

-- 3-4. CONTROL: the points and the ordering are untouched - this changes the
-- rate, not who won. If a "fix" moved these it would be rewriting results.
select is(
  (select (r->>'points')::int
     from jsonb_array_elements(public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') r
    where r->>'team_id' = :'_p'),
  2, 'the winner still has its 2 points');
select is(
  (select (public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows'->0->>'team_id')),
  :'_p', 'and still tops the group');

select * from finish();
rollback;
