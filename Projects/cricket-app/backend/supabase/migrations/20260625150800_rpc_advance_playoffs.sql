-- Progress the bracket: with both semis complete, create the final (SF1 winner v
-- SF2 winner); once the final is complete, crown the champion + mark complete.
-- Organizer-gated; idempotent at each step.
create or replace function public.advance_playoffs(_tournament_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare _t public.tournaments; _sf1w uuid; _sf2w uuid; _fw uuid; _mid uuid; _has_final boolean;
begin
  if not public.is_tournament_organizer(_tournament_id) then
    raise exception 'not authorized' using errcode = 'P0001'; end if;
  select * into _t from public.tournaments where id = _tournament_id;
  _has_final := exists (select 1 from public.tournament_matches where tournament_id = _tournament_id and stage = 'final');

  if not _has_final then
    select (m.result->>'winner_team_id')::uuid into _sf1w
      from public.tournament_matches tm join public.matches m on m.id = tm.match_id
      where tm.tournament_id = _tournament_id and tm.bracket_slot = 'SF1' and m.status = 'complete';
    select (m.result->>'winner_team_id')::uuid into _sf2w
      from public.tournament_matches tm join public.matches m on m.id = tm.match_id
      where tm.tournament_id = _tournament_id and tm.bracket_slot = 'SF2' and m.status = 'complete';
    if _sf1w is null or _sf2w is null then
      raise exception 'semifinals are not complete' using errcode = 'P0001'; end if;
    insert into public.matches(team_a_id,team_b_id,owner_id,scorer_id,overs_limit,balls_per_over,ball_type,city,status)
      values (_sf1w,_sf2w,_t.organizer_id,_t.organizer_id,_t.overs_limit,_t.balls_per_over,_t.ball_type,_t.city,'setup')
      returning id into _mid;
    insert into public.tournament_matches(match_id,tournament_id,stage,bracket_slot)
      values (_mid,_tournament_id,'final','F');
  else
    select (m.result->>'winner_team_id')::uuid into _fw
      from public.tournament_matches tm join public.matches m on m.id = tm.match_id
      where tm.tournament_id = _tournament_id and tm.stage = 'final' and m.status = 'complete';
    if _fw is null then
      raise exception 'final is not complete' using errcode = 'P0001'; end if;
    update public.tournaments set champion_team_id = _fw, status = 'complete' where id = _tournament_id;
  end if;
end; $$;
revoke all on function public.advance_playoffs(uuid) from public;
grant execute on function public.advance_playoffs(uuid) to authenticated;
