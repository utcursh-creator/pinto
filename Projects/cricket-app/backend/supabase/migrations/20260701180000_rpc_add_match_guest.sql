-- SCOR-11 / B3: let the match scorer add a guest player to EITHER participating
-- team during setup. add_guest_member is team-admin-gated, so a scorer who runs a
-- casual match can't populate the opponent's side (the practical-only path was to
-- self-create both teams - the "it's all one user, not Team A vs Team B" report).
-- Gated by is_match_scorer, and the team must actually be in the match.
create or replace function public.add_match_guest(
  _match_id uuid, _team_id uuid, _guest_name text
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid;
begin
  if not public.is_match_scorer(_match_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.matches
    where id = _match_id and _team_id in (team_a_id, team_b_id)
  ) then
    raise exception 'team is not in this match' using errcode = 'P0001';
  end if;
  insert into public.team_members (team_id, guest_name)
  values (_team_id, _guest_name)
  returning id into _id;
  return _id;
end; $$;

revoke all on function public.add_match_guest(uuid, uuid, text) from public;
grant execute on function public.add_match_guest(uuid, uuid, text) to authenticated;
