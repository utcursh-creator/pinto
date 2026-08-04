-- generate_playoffs seeds semifinals (A1 v B2, B1 v A2) from standings;
-- advance_playoffs builds the final from the semi winners and crowns the champion.
begin;
select plan(8);
select tests.create_supabase_user('org@s.dev');
-- fixture-only: linking a match to a tournament is no longer a client-granted
-- write (penetration review 2026-07-07 revoked it; fixtures are created by the
-- SECURITY DEFINER generators). Defined BEFORE authenticate_as so its definer is
-- the session owner, not the test user.
create or replace function pg_temp.link_fixture(_m uuid, _t uuid, _grp text)
returns void language plpgsql security definer as $$
begin
  insert into public.tournament_matches(match_id,tournament_id,stage,group_label)
  values (_m,_t,'group',_grp);
end; $$;

select tests.authenticate_as('org@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('org@s.dev'),'Org');

-- score an EXISTING match: team_a scores _ra, team_b scores _rb, set the result.
create or replace function pg_temp.score(_m uuid, _ra int, _rb int)
returns void language plpgsql as $$
declare _ta uuid; _tb uuid; _i uuid; _am uuid[]; _bm uuid[];
begin
  select team_a_id, team_b_id into _ta, _tb from public.matches where id=_m;
  select array(select id from public.team_members where team_id=_ta order by created_at limit 2) into _am;
  select array(select id from public.team_members where team_id=_tb order by created_at limit 2) into _bm;
  _i := public.start_innings(_m,1,_ta,_tb,_am[1],_am[2]);
  -- fixture seed: the client no longer holds a direct write grant on
  -- deliveries, so elevate for the insert only. SET ROLE back to the
  -- session user is always permitted, even from inside plpgsql.
  set local role postgres;
  insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
    select _i, gs, _bm[1], _am[1], _am[2], case when gs<=_ra then 1 else 0 end from generate_series(1,60) gs;
  set local role authenticated;
  _i := public.start_innings(_m,2,_tb,_ta,_bm[1],_bm[2]);
  -- fixture seed: the client no longer holds a direct write grant on
  -- deliveries, so elevate for the insert only. SET ROLE back to the
  -- session user is always permitted, even from inside plpgsql.
  set local role postgres;
  insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
    select _i, gs, _am[1], _bm[1], _bm[2], case when gs<=_rb then 1 else 0 end from generate_series(1,60) gs;
  set local role authenticated;
  perform public.set_match_result(_m,
    (case when _ra>_rb then 'win_by_runs' else 'win_by_wickets' end)::public.result_type,
    (case when _ra>_rb then _ta else _tb end));
end; $$;

-- create a group fixture (own match), score it, link it.
create or replace function pg_temp.group_played(_t uuid, _ta uuid, _tb uuid, _ra int, _rb int, _grp text)
returns void language plpgsql as $$
declare _m uuid;
begin
  _m := public.create_match(_ta,_tb,20,6,'{"squad_size":2}'::jsonb);
  perform pg_temp.score(_m,_ra,_rb);
  perform pg_temp.link_fixture(_m,_t,_grp);
end; $$;

select public.create_tournament('Cup', 20, 2, 2) as _t \gset
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

-- group matches: a1 beats a2; b1 beats b2 -> A1=a1, A2=a2, B1=b1, B2=b2
select pg_temp.group_played(:'_t'::uuid,:'_a1'::uuid,:'_a2'::uuid,80,40,'A');
select pg_temp.group_played(:'_t'::uuid,:'_b1'::uuid,:'_b2'::uuid,80,40,'B');

select public.generate_playoffs(:'_t'::uuid);
select is((select count(*)::int from public.tournament_matches where tournament_id=:'_t'::uuid and stage='semifinal'),
  2, 'two semifinals created');
select is((select count(*)::int from public.tournament_matches tm join public.matches m on m.id=tm.match_id
  where tm.tournament_id=:'_t'::uuid and tm.bracket_slot='SF1'
    and m.team_a_id=:'_a1'::uuid and m.team_b_id=:'_b2'::uuid), 1, 'SF1 is A1 v B2');
select is((select count(*)::int from public.tournament_matches tm join public.matches m on m.id=tm.match_id
  where tm.tournament_id=:'_t'::uuid and tm.bracket_slot='SF2'
    and m.team_a_id=:'_b1'::uuid and m.team_b_id=:'_a2'::uuid), 1, 'SF2 is B1 v A2');
select is((select status::text from public.tournaments where id=:'_t'::uuid), 'playoffs',
  'status flips to playoffs');

-- score the generated semis: a1 (SF1) and b1 (SF2) win
select pg_temp.score((select match_id from public.tournament_matches where tournament_id=:'_t'::uuid and bracket_slot='SF1'), 90, 40);
select pg_temp.score((select match_id from public.tournament_matches where tournament_id=:'_t'::uuid and bracket_slot='SF2'), 90, 40);
select public.advance_playoffs(:'_t'::uuid);
select is((select count(*)::int from public.tournament_matches where tournament_id=:'_t'::uuid and stage='final'),
  1, 'a final is created from the semi winners');
select is((select count(*)::int from public.tournament_matches tm join public.matches m on m.id=tm.match_id
  where tm.tournament_id=:'_t'::uuid and tm.stage='final'
    and m.team_a_id=:'_a1'::uuid and m.team_b_id=:'_b1'::uuid), 1, 'the final is SF1 winner (a1) v SF2 winner (b1)');

-- score the final: a1 wins -> champion
select pg_temp.score((select match_id from public.tournament_matches where tournament_id=:'_t'::uuid and stage='final'), 100, 50);
select public.advance_playoffs(:'_t'::uuid);
select is((select champion_team_id from public.tournaments where id=:'_t'::uuid), :'_a1'::uuid, 'champion = a1');
select is((select status::text from public.tournaments where id=:'_t'::uuid), 'complete', 'tournament is complete');

select * from finish();
rollback;
