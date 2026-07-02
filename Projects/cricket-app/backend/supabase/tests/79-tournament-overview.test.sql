-- Integration: a full 2-group x 2-team tournament played end to end through the
-- real RPCs (create -> add teams -> generate_group_fixtures -> score -> generate
-- playoffs -> score -> advance -> final -> advance -> champion). Asserts the
-- composed overview + that anon can read it.
begin;
select plan(9);
select tests.create_supabase_user('org@s.dev');
select tests.authenticate_as('org@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('org@s.dev'),'Org');

-- score an existing match: team_a wins (scores 60 to team_b's 30).
create or replace function pg_temp.win_a(_m uuid)
returns void language plpgsql as $$
declare _ta uuid; _tb uuid; _i uuid; _am uuid[]; _bm uuid[];
begin
  select team_a_id, team_b_id into _ta, _tb from public.matches where id=_m;
  select array(select id from public.team_members where team_id=_ta order by created_at limit 2) into _am;
  select array(select id from public.team_members where team_id=_tb order by created_at limit 2) into _bm;
  _i := public.start_innings(_m,1,_ta,_tb,_am[1],_am[2]);
  insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
    select _i, gs, _bm[1], _am[1], _am[2], case when gs<=60 then 1 else 0 end from generate_series(1,120) gs;
  _i := public.start_innings(_m,2,_tb,_ta,_bm[1],_bm[2]);
  insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
    select _i, gs, _am[1], _bm[1], _bm[2], case when gs<=30 then 1 else 0 end from generate_series(1,120) gs;
  perform public.set_match_result(_m,'win_by_runs'::public.result_type,_ta);
end; $$;

select public.create_tournament('League', 20, 2, 2) as _t \gset
select public.create_team('a1','C') as _a1 \gset
select public.create_team('a2','C') as _a2 \gset
select public.create_team('b1','C') as _b1 \gset
select public.create_team('b2','C') as _b2 \gset
select public.add_guest_member(:'_a1'::uuid,'p'); select public.add_guest_member(:'_a1'::uuid,'q');
select public.add_guest_member(:'_a2'::uuid,'p'); select public.add_guest_member(:'_a2'::uuid,'q');
select public.add_guest_member(:'_b1'::uuid,'p'); select public.add_guest_member(:'_b1'::uuid,'q');
select public.add_guest_member(:'_b2'::uuid,'p'); select public.add_guest_member(:'_b2'::uuid,'q');
select public.add_tournament_team(:'_t'::uuid,:'_a1'::uuid,'A');
select public.add_tournament_team(:'_t'::uuid,:'_a2'::uuid,'A');
select public.add_tournament_team(:'_t'::uuid,:'_b1'::uuid,'B');
select public.add_tournament_team(:'_t'::uuid,:'_b2'::uuid,'B');

-- group stage via the real generator, then score every group match (team_a wins)
select public.generate_group_fixtures(:'_t'::uuid);
select pg_temp.win_a(match_id) from public.tournament_matches where tournament_id=:'_t'::uuid and stage='group';

-- playoffs
select public.generate_playoffs(:'_t'::uuid);
select pg_temp.win_a(match_id) from public.tournament_matches where tournament_id=:'_t'::uuid and stage='semifinal';
select public.advance_playoffs(:'_t'::uuid);  -- creates the final
select pg_temp.win_a(match_id) from public.tournament_matches where tournament_id=:'_t'::uuid and stage='final';
select public.advance_playoffs(:'_t'::uuid);  -- crowns the champion

select isnt((select champion_team_id from public.tournaments where id=:'_t'::uuid), null::uuid,
  'a champion is crowned');
select is((select status::text from public.tournaments where id=:'_t'::uuid), 'complete',
  'tournament is complete');
select is(jsonb_array_length(public.tournament_standings(:'_t'::uuid)->'groups'), 2,
  'standings cover both groups');
select isnt(public.tournament_leaderboard(:'_t'::uuid)->'most_runs'->0->>'member_id', null,
  'the leaderboard has a top run-scorer');

-- overview composition (anon-readable)
select tests.clear_authentication();
select is(public.tournament_overview(:'_t'::uuid)->'tournament'->>'name', 'League',
  'anon overview includes the tournament name');
select isnt(public.tournament_overview(:'_t'::uuid)->>'champion_team_id', null,
  'anon overview includes the champion');
select is(jsonb_array_length(public.tournament_overview(:'_t'::uuid)->'fixtures'), 5,
  'overview lists all 5 fixtures (2 group + 2 semis + final)');

-- TOUR-6: each completed fixture carries its two innings scores + winner, so a
-- tile can render "A 60/0 beat B 30". team_a wins every match 60 to 30.
select is(
  (select (f->'innings'->0->>'runs')::int
     from jsonb_array_elements(public.tournament_overview(:'_t'::uuid)->'fixtures') f
     where jsonb_array_length(f->'innings') = 2 limit 1),
  60, 'a completed fixture exposes its first-innings runs');
select is(
  (select f->'result'->>'result_type'
     from jsonb_array_elements(public.tournament_overview(:'_t'::uuid)->'fixtures') f
     where jsonb_array_length(f->'innings') = 2 limit 1),
  'win_by_runs', 'a completed fixture exposes its result type + winner');

select * from finish();
rollback;
