-- tournament_standings: points (win 2), NRR with the ICC all-out full-quota
-- rule, and ordering by points then NRR. Matches use rules squad_size=2 so a
-- single wicket = all out, making totals/overs hand-controllable.
-- Group A: X beats Z + Y (4 pts), Y beats Z (2 pts), Z loses both (0 pts).
-- X v Z: Z is ALL OUT for 50, so its overs count as the full 20 (not the ~8 it
-- faced) - that makes X's NRR exactly 1.75 (it would be 0.54 without the rule).
begin;
select plan(6);
select tests.create_supabase_user('org@s.dev');
select tests.authenticate_as('org@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('org@s.dev'),'Org');
select public.create_tournament('Cup', 20, 1, 2) as _t \gset
select public.create_team('X','C') as _x \gset
select public.create_team('Y','C') as _y \gset
select public.create_team('Z','C') as _z \gset
select public.add_guest_member(:'_x'::uuid,'x1') as _x1 \gset
select public.add_guest_member(:'_x'::uuid,'x2') as _x2 \gset
select public.add_guest_member(:'_x'::uuid,'xb') as _xb \gset
select public.add_guest_member(:'_y'::uuid,'y1') as _y1 \gset
select public.add_guest_member(:'_y'::uuid,'y2') as _y2 \gset
select public.add_guest_member(:'_y'::uuid,'yb') as _yb \gset
select public.add_guest_member(:'_z'::uuid,'z1') as _z1 \gset
select public.add_guest_member(:'_z'::uuid,'z2') as _z2 \gset
select public.add_guest_member(:'_z'::uuid,'zb') as _zb \gset

-- enter all three teams into the tournament (group A). The organizer created
-- them so passes the SEC-8 team-admin gate; standings now seed from these.
select public.add_tournament_team(:'_t'::uuid, :'_x'::uuid, 'A');
select public.add_tournament_team(:'_t'::uuid, :'_y'::uuid, 'A');
select public.add_tournament_team(:'_t'::uuid, :'_z'::uuid, 'A');

-- helper note: bat(_in, bowler, striker, non, runs) inserts `runs` ones over 120
-- legal balls (not all out, full 20 overs); allout(_in, bowler, s, ns, runs)
-- inserts `runs` ones then a wicket (all out -> full-quota overs).

-- Match X v Z: X 100 (20 ov, not out), Z all out 50 -> X wins by runs
select public.create_match(:'_x'::uuid,:'_z'::uuid,20,6,'{"squad_size":2}'::jsonb) as _mxz \gset
select public.start_innings(:'_mxz'::uuid,1,:'_x'::uuid,:'_z'::uuid,:'_x1'::uuid,:'_x2'::uuid) as _ixz1 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_ixz1'::uuid, gs, :'_zb'::uuid, :'_x1'::uuid, :'_x2'::uuid, case when gs<=100 then 1 else 0 end from generate_series(1,120) gs;
set local role :_seedrole;
select public.start_innings(:'_mxz'::uuid,2,:'_z'::uuid,:'_x'::uuid,:'_z1'::uuid,:'_z2'::uuid) as _ixz2 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_ixz2'::uuid, gs, :'_xb'::uuid, :'_z1'::uuid, :'_z2'::uuid, 1 from generate_series(1,50) gs;
set local role :_seedrole;
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type)
  values (:'_ixz2'::uuid,51,:'_xb'::uuid,:'_z1'::uuid,:'_z2'::uuid,'bowled');
set local role :_seedrole;
select public.set_match_result(:'_mxz'::uuid,'win_by_runs'::public.result_type,:'_x'::uuid);
reset role;  -- fixture setup: this write is no longer granted to clients
insert into public.tournament_matches(match_id,tournament_id,stage,group_label) values (:'_mxz'::uuid,:'_t'::uuid,'group','A');
select tests.authenticate_as('org@s.dev');

-- Match X v Y: X 90 (20 ov), Y 70 (20 ov) -> X wins
select public.create_match(:'_x'::uuid,:'_y'::uuid,20,6,'{"squad_size":2}'::jsonb) as _mxy \gset
select public.start_innings(:'_mxy'::uuid,1,:'_x'::uuid,:'_y'::uuid,:'_x1'::uuid,:'_x2'::uuid) as _ixy1 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_ixy1'::uuid, gs, :'_yb'::uuid, :'_x1'::uuid, :'_x2'::uuid, case when gs<=90 then 1 else 0 end from generate_series(1,120) gs;
set local role :_seedrole;
select public.start_innings(:'_mxy'::uuid,2,:'_y'::uuid,:'_x'::uuid,:'_y1'::uuid,:'_y2'::uuid) as _ixy2 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_ixy2'::uuid, gs, :'_xb'::uuid, :'_y1'::uuid, :'_y2'::uuid, case when gs<=70 then 1 else 0 end from generate_series(1,120) gs;
set local role :_seedrole;
select public.set_match_result(:'_mxy'::uuid,'win_by_runs'::public.result_type,:'_x'::uuid);
reset role;  -- fixture setup: this write is no longer granted to clients
insert into public.tournament_matches(match_id,tournament_id,stage,group_label) values (:'_mxy'::uuid,:'_t'::uuid,'group','A');
select tests.authenticate_as('org@s.dev');

-- Match Y v Z: Y 80 (20 ov), Z 60 (20 ov) -> Y wins
select public.create_match(:'_y'::uuid,:'_z'::uuid,20,6,'{"squad_size":2}'::jsonb) as _myz \gset
select public.start_innings(:'_myz'::uuid,1,:'_y'::uuid,:'_z'::uuid,:'_y1'::uuid,:'_y2'::uuid) as _iyz1 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_iyz1'::uuid, gs, :'_zb'::uuid, :'_y1'::uuid, :'_y2'::uuid, case when gs<=80 then 1 else 0 end from generate_series(1,120) gs;
set local role :_seedrole;
select public.start_innings(:'_myz'::uuid,2,:'_z'::uuid,:'_y'::uuid,:'_z1'::uuid,:'_z2'::uuid) as _iyz2 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_iyz2'::uuid, gs, :'_yb'::uuid, :'_z1'::uuid, :'_z2'::uuid, case when gs<=60 then 1 else 0 end from generate_series(1,120) gs;
set local role :_seedrole;
select public.set_match_result(:'_myz'::uuid,'win_by_runs'::public.result_type,:'_y'::uuid);
reset role;  -- fixture setup: this write is no longer granted to clients
insert into public.tournament_matches(match_id,tournament_id,stage,group_label) values (:'_myz'::uuid,:'_t'::uuid,'group','A');
select tests.authenticate_as('org@s.dev');

-- standings: a function reading group A rows, sorted points desc then NRR desc
select is((select (e->>'points')::int from jsonb_array_elements(
  public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') e where e->>'team_id'=:'_x'), 4, 'X has 4 points');
select is((select (e->>'points')::int from jsonb_array_elements(
  public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') e where e->>'team_id'=:'_y'), 2, 'Y has 2 points');
select is((select (e->>'points')::int from jsonb_array_elements(
  public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') e where e->>'team_id'=:'_z'), 0, 'Z has 0 points');
select is((select (e->>'nrr')::numeric from jsonb_array_elements(
  public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') e where e->>'team_id'=:'_x'), 1.750,
  'X NRR = 1.75 (validates the all-out full-quota rule)');
select is(
  (public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows'->0->>'team_id'),
  (:'_x'::uuid)::text, 'X is top of the group (most points)');
select is((select (e->>'won')::int from jsonb_array_elements(
  public.tournament_standings(:'_t'::uuid)->'groups'->0->'rows') e where e->>'team_id'=:'_x'), 2, 'X won 2');

select * from finish();
rollback;
