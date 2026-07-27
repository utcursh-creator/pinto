-- HIGH (penetration review 2026-07-07, idor-add-squad-member-career-forgery):
-- add_squad_member checked only that the caller is the match scorer, then took
-- _team_id and _team_member_id on trust. A scorer could therefore name ANY team
-- and ANY player - including strangers - and, once a ball was scored, bake a
-- permanent, publicly-readable career record (a golden duck, a bowling figure)
-- for someone who never played, with no user-facing way to remove it.
-- add_match_guest already validates exactly this shape (20260703180100); this
-- brings add_squad_member in line.
--
-- Also adds `on conflict do update`: re-adding a squad member used to raise a
-- duplicate-key error, which is what permanently stranded a resumed match setup
-- (error-ux: "Resuming match setup always dies on a raw duplicate-key error").
create or replace function public.add_squad_member(
  _match_id uuid, _team_id uuid, _team_member_id uuid,
  _batting_order int default null, _is_captain boolean default false, _is_keeper boolean default false
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid;
begin
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;

  if not exists (select 1 from public.matches m
                  where m.id = _match_id and _team_id in (m.team_a_id, m.team_b_id)) then
    raise exception 'that team is not in this match' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.team_members tm
                  where tm.id = _team_member_id and tm.team_id = _team_id) then
    raise exception 'that player is not in that team' using errcode = 'P0001';
  end if;

  insert into public.match_squad(match_id,team_id,team_member_id,batting_order,is_captain,is_wicket_keeper)
  values (_match_id,_team_id,_team_member_id,_batting_order,_is_captain,_is_keeper)
  on conflict (match_id, team_member_id) do update
    set team_id = excluded.team_id,
        batting_order = excluded.batting_order,
        is_captain = excluded.is_captain,
        is_wicket_keeper = excluded.is_wicket_keeper
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.add_squad_member(uuid,uuid,uuid,int,boolean,boolean) from public;
grant execute on function public.add_squad_member(uuid,uuid,uuid,int,boolean,boolean) to authenticated;

-- the direct-table path must enforce the same participant rule, or the RPC's
-- validation is just advice (match_squad is granted to authenticated).
drop policy if exists "match_squad_write_scorer" on public.match_squad;
create policy "match_squad_write_scorer" on public.match_squad
  for all to authenticated
  using (public.is_match_scorer(match_id))
  with check (
    public.is_match_scorer(match_id)
    and exists (select 1 from public.matches m
                 where m.id = match_id and team_id in (m.team_a_id, m.team_b_id))
    and exists (select 1 from public.team_members tm
                 where tm.id = team_member_id and tm.team_id = match_squad.team_id)
  );
