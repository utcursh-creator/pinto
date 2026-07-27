-- tournament_leaderboard ranks players across a tournament's completed matches;
-- match_potm picks the highest-impact player (runs + 20*wkts + 10*dismissals)
-- with a winning-side tiebreak.
-- One match: x1 makes 20 (5 fours) then is caught by zf off zb; z1 makes 5. X wins.
begin;
select plan(8);
select tests.create_supabase_user('org@s.dev');
select tests.authenticate_as('org@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('org@s.dev'),'Org');
select public.create_tournament('Cup', 20, 1, 2) as _t \gset
select public.create_team('X','C') as _x \gset
select public.create_team('Z','C') as _z \gset
select public.add_guest_member(:'_x'::uuid,'x1') as _x1 \gset
select public.add_guest_member(:'_x'::uuid,'x2') as _x2 \gset
select public.add_guest_member(:'_x'::uuid,'xb') as _xb \gset
select public.add_guest_member(:'_z'::uuid,'z1') as _z1 \gset
select public.add_guest_member(:'_z'::uuid,'z2') as _z2 \gset
select public.add_guest_member(:'_z'::uuid,'zb') as _zb \gset
select public.add_guest_member(:'_z'::uuid,'zf') as _zf \gset

select public.create_match(:'_x'::uuid,:'_z'::uuid,20,6,'{"squad_size":2}'::jsonb) as _m \gset
-- innings 1: X bats, zb bowls. x1 hits 5 fours (20), then caught by zf -> all out.
select public.start_innings(:'_m'::uuid,1,:'_x'::uuid,:'_z'::uuid,:'_x1'::uuid,:'_x2'::uuid) as _i1 \gset
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_i1'::uuid, gs, :'_zb'::uuid, :'_x1'::uuid, :'_x2'::uuid, 4 from generate_series(1,5) gs;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,fielder_id)
  values (:'_i1'::uuid,6,:'_zb'::uuid,:'_x1'::uuid,:'_x2'::uuid,'caught',:'_zf'::uuid);
-- innings 2: Z bats, xb bowls. z1 makes 5, not out.
select public.start_innings(:'_m'::uuid,2,:'_z'::uuid,:'_x'::uuid,:'_z1'::uuid,:'_z2'::uuid) as _i2 \gset
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_i2'::uuid, gs, :'_xb'::uuid, :'_z1'::uuid, :'_z2'::uuid, 1 from generate_series(1,5) gs;
select public.set_match_result(:'_m'::uuid,'win_by_runs'::public.result_type,:'_x'::uuid);
reset role;  -- fixture setup: this write is no longer granted to clients
insert into public.tournament_matches(match_id,tournament_id,stage,group_label) values (:'_m'::uuid,:'_t'::uuid,'group','A');
select tests.authenticate_as('org@s.dev');

select is((public.tournament_leaderboard(:'_t'::uuid)->'most_runs'->0->>'member_id'), (:'_x1'::uuid)::text,
  'top run-scorer is x1');
select is((public.tournament_leaderboard(:'_t'::uuid)->'most_runs'->0->>'runs')::int, 20,
  'x1 scored 20');
select is((public.tournament_leaderboard(:'_t'::uuid)->'most_fours'->0->>'member_id'), (:'_x1'::uuid)::text,
  'most fours is x1');
select is((public.tournament_leaderboard(:'_t'::uuid)->'most_wickets'->0->>'member_id'), (:'_zb'::uuid)::text,
  'top wicket-taker is zb');
select is((public.tournament_leaderboard(:'_t'::uuid)->'most_catches'->0->>'member_id'), (:'_zf'::uuid)::text,
  'top fielder is zf');
-- POTM: x1 (impact 20, winning side) beats zb (impact 20, losing side) on the tiebreak
select is((public.match_potm(:'_m'::uuid)->>'member_id'), (:'_x1'::uuid)::text,
  'POTM is x1 (winning-side tiebreak over zb at equal impact)');

-- TOUR-7: rows expose a profile_id key so claimed players can link to /player/:id
select ok((public.tournament_leaderboard(:'_t'::uuid)->'most_runs'->0) ? 'profile_id',
  'leaderboard rows carry a profile_id key');
select ok(public.match_potm(:'_m'::uuid) ? 'profile_id',
  'POTM carries a profile_id key');

select * from finish();
rollback;
