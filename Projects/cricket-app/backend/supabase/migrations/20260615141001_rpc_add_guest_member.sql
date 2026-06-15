create or replace function public.add_guest_member(_team_id uuid, _guest_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  _id uuid;
begin
  if not public.is_team_admin(_team_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;

  insert into public.team_members (team_id, guest_name)
  values (_team_id, _guest_name)
  returning id into _id;

  return _id;
end;
$$;

revoke all on function public.add_guest_member(uuid, text) from public;
grant execute on function public.add_guest_member(uuid, text) to authenticated;
