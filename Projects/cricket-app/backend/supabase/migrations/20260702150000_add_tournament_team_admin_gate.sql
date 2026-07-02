-- SEC-8: add_tournament_team enrolled ANY team without that team's consent (and
-- then auto-generated real fixtures for them). Require the organizer to also be
-- an admin of the team being entered. For the dominant casual pattern the
-- organizer creates the teams themselves (so they are the admin); enrolling a
-- team owned by someone else is deferred to a future tournament_invites accept
-- flow rather than left as an unconsented insert.
create or replace function public.add_tournament_team(
  _tournament_id uuid, _team_id uuid, _group_label text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_tournament_organizer(_tournament_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if not public.is_team_admin(_team_id) then
    raise exception 'you must be an admin of this team to enter it' using errcode = 'P0001';
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
