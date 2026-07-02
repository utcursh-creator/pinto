-- TEAM-6 (same guard as add_guest_member): the wizard's add_match_guest also
-- trims, rejects empty names, and rejects a case-insensitive duplicate guest on
-- the same team.
create or replace function public.add_match_guest(
  _match_id uuid, _team_id uuid, _guest_name text
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid; _name text := trim(coalesce(_guest_name, ''));
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
  if length(_name) < 1 then
    raise exception 'a guest needs a name' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.team_members
    where team_id = _team_id and lower(guest_name) = lower(_name)
  ) then
    raise exception 'a guest with this name is already on the team' using errcode = 'P0001';
  end if;
  insert into public.team_members (team_id, guest_name)
  values (_team_id, _name)
  returning id into _id;
  return _id;
end; $$;

revoke all on function public.add_match_guest(uuid, uuid, text) from public;
grant execute on function public.add_match_guest(uuid, uuid, text) to authenticated;
