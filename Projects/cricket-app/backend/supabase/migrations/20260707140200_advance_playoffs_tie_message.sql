-- HIGH (penetration review 2026-07-07, completeness critic - part 2):
-- advance_playoffs read the winner and, finding null, said "semifinals are not
-- complete". For a TIED semifinal that is simply false - the match IS complete -
-- so the organizer was told to finish a match they had already finished, with no
-- hint about what was actually wrong or what to do. Now it names the tie and
-- points at resolve_tied_fixture.
create or replace function public.advance_playoffs(_tournament_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  _t public.tournaments; _has_final boolean; _sf1w uuid; _sf2w uuid; _fw uuid; _mid uuid;
  _tied_slot text;
begin
  select * into _t from public.tournaments where id = _tournament_id;
  if _t.id is null then raise exception 'tournament not found' using errcode = 'P0001'; end if;
  if not public.is_tournament_organizer(_tournament_id) then
    raise exception 'not authorized' using errcode = 'P0001'; end if;

  -- A knockout that finished LEVEL is complete but has no winner. Say so.
  select tm.bracket_slot into _tied_slot
    from public.tournament_matches tm join public.matches m on m.id = tm.match_id
   where tm.tournament_id = _tournament_id
     and tm.stage in ('semifinal','final')
     and m.status = 'complete'
     and (m.result->>'winner_team_id') is null
   limit 1;
  if _tied_slot is not null then
    raise exception '% finished level - record who won the super over to break the tie', _tied_slot
      using errcode = 'P0001';
  end if;

  select exists (
    select 1 from public.tournament_matches tm
     where tm.tournament_id = _tournament_id and tm.stage = 'final'
  ) into _has_final;

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
