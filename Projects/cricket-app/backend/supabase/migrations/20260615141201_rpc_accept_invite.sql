create or replace function public.accept_invite(_invite_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  _team_id uuid;
  _membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select team_id into _team_id
  from public.team_invites
  where invite_token = _invite_token and status = 'pending';

  if _team_id is null then
    raise exception 'invite not found or already used' using errcode = 'P0001';
  end if;

  -- Concurrency-safe: rely on the partial unique index instead of a read-then-insert race.
  insert into public.team_members (team_id, profile_id, role)
  values (_team_id, auth.uid(), 'player')
  on conflict (team_id, profile_id) where profile_id is not null
  do nothing
  returning id into _membership_id;

  if _membership_id is null then
    select id into _membership_id
    from public.team_members
    where team_id = _team_id and profile_id = auth.uid();
  end if;

  update public.team_invites set status = 'accepted' where invite_token = _invite_token;

  return _membership_id;
end;
$$;

revoke all on function public.accept_invite(text) from public;
grant execute on function public.accept_invite(text) to authenticated;
