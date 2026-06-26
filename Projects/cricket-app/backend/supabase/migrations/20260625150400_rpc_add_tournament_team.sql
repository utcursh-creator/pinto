create or replace function public.add_tournament_team(
  _tournament_id uuid, _team_id uuid, _group_label text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_tournament_organizer(_tournament_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if (select status from public.tournaments where id = _tournament_id) <> 'setup' then
    raise exception 'tournament is not in setup' using errcode = 'P0001';
  end if;
  insert into public.tournament_teams(tournament_id, team_id, group_label)
  values (_tournament_id, _team_id, _group_label)
  on conflict (tournament_id, team_id) do update set group_label = excluded.group_label;
end; $$;
revoke all on function public.add_tournament_team(uuid,uuid,text) from public;
grant execute on function public.add_tournament_team(uuid,uuid,text) to authenticated;
