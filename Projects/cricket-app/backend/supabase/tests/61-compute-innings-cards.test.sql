-- compute_innings_cards: a multi-player generalization of compute_innings_state.
-- Emits per-player batting / bowling / fielding lines for ONE innings, folding
-- the same rules (strike rotation, count_noball_as_ball_faced, bowler-credited
-- wicket set, maiden over-window, dismissal attribution). The two folds must NOT
-- diverge - the divergence-guard assertions below cross-check cards totals
-- against compute_innings_state on the same fixture.
begin;
select plan(22);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid,'B3') as _b3 \gset
select public.add_guest_member(:'_a'::uuid,'B4') as _b4 \gset
select public.add_guest_member(:'_a'::uuid,'B5') as _b5 \gset
select public.add_guest_member(:'_b'::uuid,'Bowl') as _bw \gset
select public.add_guest_member(:'_b'::uuid,'Fd')   as _fd \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

-- A rich one-over+ innings exercising every attribution path. striker_id stamps
-- below are illustrative; the fold re-derives strike, so cards must agree with it.
-- seq1: S off-bat 1 (rotate -> NS on strike)
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1);
-- seq2: wide to NS (not legal, not faced)
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_wides) values
 (:'_in'::uuid,2,:'_bw'::uuid,:'_ns'::uuid,:'_s'::uuid,1);
-- seq3: no-ball to NS (faced when count_noball_as_ball_faced=true; sets free hit)
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_no_ball_penalty) values
 (:'_in'::uuid,3,:'_bw'::uuid,:'_ns'::uuid,:'_s'::uuid,1);
-- seq4 (free hit): NS off-bat 6
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,4,:'_bw'::uuid,:'_ns'::uuid,:'_s'::uuid,6);
-- seq5: NS bowled (null dismissed_player_id -> on-strike), incoming B3
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,incoming_batter_id) values
 (:'_in'::uuid,5,:'_bw'::uuid,:'_ns'::uuid,:'_s'::uuid,'bowled',:'_b3'::uuid);
-- seq6: B3 off-bat 4
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,6,:'_bw'::uuid,:'_b3'::uuid,:'_s'::uuid,4);
-- seq7: B3 caught (null dismissed_player_id -> on-strike), fielder Fd, incoming B4
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,fielder_id,incoming_batter_id) values
 (:'_in'::uuid,7,:'_bw'::uuid,:'_b3'::uuid,:'_s'::uuid,'caught',:'_fd'::uuid,:'_b4'::uuid);
-- seq8: run out of S (the non-striker), fielder Fd, incoming B5 (over also ends here)
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,dismissed_player_id,fielder_id,incoming_batter_id) values
 (:'_in'::uuid,8,:'_bw'::uuid,:'_b4'::uuid,:'_s'::uuid,'run_out',:'_s'::uuid,:'_fd'::uuid,:'_b5'::uuid);
-- seq9: B5 retired_not_out (NOT a dismissal). Since fold v14 a retirement is a
-- non-ball EVENT row, never a delivery - recording it as a ball consumed a ball
-- and charged the bowler. A CHECK constraint now enforces that.
insert into public.deliveries(innings_id,seq,event_kind,striker_id,non_striker_id,wicket_type,dismissed_player_id) values
 (:'_in'::uuid,9,'retirement',:'_b5'::uuid,:'_b4'::uuid,'retired_not_out',:'_b5'::uuid);

-- ---- batting lines (resolved per-player, dismissal attribution) ----
select is((select (e->>'runs')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_s'),
  1, 'S scored 1');
select is((select e->>'how_out' from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_s'),
  'run_out', 'S out: run_out attributed via dismissed_player_id (the non-striker)');
select is((select (e->>'runs')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_ns'),
  6, 'NS scored 6');
select is((select (e->>'sixes')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_ns'),
  1, 'NS hit one six');
select is((select (e->>'balls')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_ns'),
  3, 'NS faced 3 (no-ball counted; wide not)');
select is((select e->>'how_out' from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_ns'),
  'bowled', 'NS out: bowled attributed to the on-strike batter (null dismissed_player_id)');
select is((select (e->>'runs')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_b3'),
  4, 'B3 scored 4');
select is((select (e->>'fours')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_b3'),
  1, 'B3 hit one four');
select is((select e->>'how_out' from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_b3'),
  'caught', 'B3 out: caught attributed to the on-strike batter');
select is((select (e->>'dismissed')::boolean from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_b4'),
  false, 'B4 not dismissed (faced the run-out ball but survived)');
select is((select (e->>'dismissed')::boolean from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where e->>'member_id'=:'_b5'),
  false, 'B5 retired_not_out is NOT a dismissal');

-- ---- bowling line ----
-- 6, not 7: seq9 is a RETIREMENT, which is an event between balls. It used to be
-- stored as a delivery, so the bowler was charged a legal ball for a batter
-- walking off - the exact corruption fold v14's event rows removed.
select is((select (e->>'legal_balls')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'bowling') e where e->>'member_id'=:'_bw'),
  6, 'Bowl: 6 legal balls (wide, no-ball and the retirement event excluded)');
select is((select (e->>'wickets')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'bowling') e where e->>'member_id'=:'_bw'),
  2, 'Bowl: 2 wickets (bowled + caught; run_out NOT credited)');
select is((select (e->>'runs_conceded')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'bowling') e where e->>'member_id'=:'_bw'),
  13, 'Bowl: 13 conceded (off-bat 11 + wide 1 + no-ball 1)');
select is((select (e->>'wides')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'bowling') e where e->>'member_id'=:'_bw'),
  1, 'Bowl: 1 wide');
select is((select (e->>'no_balls')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'bowling') e where e->>'member_id'=:'_bw'),
  1, 'Bowl: 1 no-ball');

-- ---- fielding line ----
select is((select (e->>'catches')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'fielding') e where e->>'member_id'=:'_fd'),
  1, 'Fd: 1 catch');
select is((select (e->>'run_outs')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'fielding') e where e->>'member_id'=:'_fd'),
  1, 'Fd: 1 run-out');

-- ---- divergence guards: cards MUST agree with compute_innings_state ----
select is(
  (select (e->>'legal_balls')::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'bowling') e where e->>'member_id'=:'_bw'),
  (public.compute_innings_state(:'_in'::uuid)->>'legal_balls')::int,
  'divergence guard: bowler legal_balls = state legal_balls');
select is(
  (select count(*)::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e where (e->>'dismissed')::boolean),
  (public.compute_innings_state(:'_in'::uuid)->>'wickets')::int,
  'divergence guard: dismissed batters = state wickets (3)');
select is(
  (select sum((e->>'runs')::int)::int from jsonb_array_elements(public.compute_innings_cards(:'_in'::uuid)->'batting') e),
  11, 'divergence guard: total off-bat runs = 11');

-- ---- count_noball_as_ball_faced=false branch ----
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,6,'{"count_noball_as_ball_faced":false}'::jsonb) as _mt2 \gset
select public.start_innings(:'_mt2'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in2 \gset
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_no_ball_penalty) values
 (:'_in2'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1);
select is(
  (select (e->>'balls')::int from jsonb_array_elements(public.compute_innings_cards(:'_in2'::uuid)->'batting') e where e->>'member_id'=:'_s'),
  0, 'count_noball_as_ball_faced=false: a faced no-ball is NOT a ball faced');

select * from finish();
rollback;
