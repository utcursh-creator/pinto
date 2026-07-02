-- TEAM-6: add_guest_member accepted any _guest_name including empty/whitespace
-- (rendering the "Guest" fallback) and silent duplicates. Trim server-side,
-- reject empty, and reject a case-insensitive duplicate guest on the same team
-- (the admin can still add "Rahul S" if "Rahul" exists).
create or replace function public.add_guest_member(_team_id uuid, _guest_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  _id uuid; _name text := trim(coalesce(_guest_name, ''));
begin
  if not public.is_team_admin(_team_id) then
    raise exception 'not authorized' using errcode = 'P0001';
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
end;
$$;

revoke all on function public.add_guest_member(uuid, text) from public;
grant execute on function public.add_guest_member(uuid, text) to authenticated;
