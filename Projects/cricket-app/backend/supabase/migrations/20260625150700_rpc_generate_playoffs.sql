-- Seed the semifinals from group standings: SF1 = A1 v B2, SF2 = B1 v A2
-- (cross-seed so group winners avoid an immediate rematch). v1 supports the
-- 4-qualifier shape (2 groups x 2 qualifiers). Organizer-gated; requires every
-- group match complete; idempotent.
create or replace function public.generate_playoffs(_tournament_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare _t public.tournaments; _st jsonb; _a1 uuid; _a2 uuid; _b1 uuid; _b2 uuid; _mid uuid;
begin
  if not public.is_tournament_organizer(_tournament_id) then
    raise exception 'not authorized' using errcode = 'P0001'; end if;
  select * into _t from public.tournaments where id = _tournament_id;
  if _t.group_count <> 2 or _t.qualifiers_per_group <> 2 then
    raise exception 'v1 supports 2 groups x 2 qualifiers only' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.tournament_matches where tournament_id = _tournament_id and stage = 'group') then
    raise exception 'no group fixtures' using errcode = 'P0001'; end if;
  if exists (select 1 from public.tournament_matches tm join public.matches m on m.id = tm.match_id
             where tm.tournament_id = _tournament_id and tm.stage = 'group' and m.status <> 'complete') then
    raise exception 'group stage is not complete' using errcode = 'P0001'; end if;
  if exists (select 1 from public.tournament_matches where tournament_id = _tournament_id
             and stage in ('semifinal','final')) then
    raise exception 'playoffs already generated' using errcode = 'P0001'; end if;

  _st := public.tournament_standings(_tournament_id);
  _a1 := (_st->'groups'->0->'rows'->0->>'team_id')::uuid;
  _a2 := (_st->'groups'->0->'rows'->1->>'team_id')::uuid;
  _b1 := (_st->'groups'->1->'rows'->0->>'team_id')::uuid;
  _b2 := (_st->'groups'->1->'rows'->1->>'team_id')::uuid;
  if _a1 is null or _a2 is null or _b1 is null or _b2 is null then
    raise exception 'not enough qualified teams' using errcode = 'P0001'; end if;

  insert into public.matches(team_a_id,team_b_id,owner_id,scorer_id,overs_limit,balls_per_over,ball_type,city,status)
    values (_a1,_b2,_t.organizer_id,_t.organizer_id,_t.overs_limit,_t.balls_per_over,_t.ball_type,_t.city,'setup')
    returning id into _mid;
  insert into public.tournament_matches(match_id,tournament_id,stage,bracket_slot)
    values (_mid,_tournament_id,'semifinal','SF1');
  insert into public.matches(team_a_id,team_b_id,owner_id,scorer_id,overs_limit,balls_per_over,ball_type,city,status)
    values (_b1,_a2,_t.organizer_id,_t.organizer_id,_t.overs_limit,_t.balls_per_over,_t.ball_type,_t.city,'setup')
    returning id into _mid;
  insert into public.tournament_matches(match_id,tournament_id,stage,bracket_slot)
    values (_mid,_tournament_id,'semifinal','SF2');

  update public.tournaments set status = 'playoffs' where id = _tournament_id;
end; $$;
revoke all on function public.generate_playoffs(uuid) from public;
grant execute on function public.generate_playoffs(uuid) to authenticated;
