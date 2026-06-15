create or replace function public.create_team(_name text, _city text default null, _logo_url text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  _team_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  insert into public.teams (name, city, logo_url, created_by)
  values (_name, _city, _logo_url, auth.uid())
  returning id into _team_id;

  insert into public.team_members (team_id, profile_id, role)
  values (_team_id, auth.uid(), 'captain');

  return _team_id;
end;
$$;

revoke all on function public.create_team(text, text, text) from public;
grant execute on function public.create_team(text, text, text) to authenticated;
