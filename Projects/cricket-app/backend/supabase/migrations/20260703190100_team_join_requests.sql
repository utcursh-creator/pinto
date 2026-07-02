-- TEAM-11: a stranger's team page was a read-only dead end. A signed-in user
-- can now REQUEST to join; a team admin approves (-> player membership) or
-- declines. Admins are notified through the existing notifications inbox.
create table public.team_join_requests (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid not null references public.teams(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  status       public.claim_status not null default 'pending',
  created_at   timestamptz not null default now(),
  unique (team_id, requester_id)
);

alter table public.team_join_requests enable row level security;
grant select on public.team_join_requests to authenticated;

-- Read: the requester sees their own; admins see their team's. Writes go
-- through the SECURITY DEFINER RPCs only.
create policy "join_requests_select" on public.team_join_requests
  for select to authenticated
  using (requester_id = (select auth.uid()) or public.is_team_admin(team_id));

create or replace function public.request_to_join(_team_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare _me uuid := (select auth.uid()); _id uuid;
begin
  if _me is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if exists (select 1 from public.team_members
             where team_id = _team_id and profile_id = _me) then
    raise exception 'you are already on this team' using errcode='P0001';
  end if;
  if exists (select 1 from public.team_join_requests
             where team_id = _team_id and requester_id = _me and status = 'pending') then
    raise exception 'request already pending' using errcode='P0001';
  end if;

  insert into public.team_join_requests(team_id, requester_id)
  values (_team_id, _me)
  on conflict (team_id, requester_id)
    do update set status = 'pending', created_at = now()
  returning id into _id;

  -- tell the admins (best-effort; inbox row per admin)
  begin
    insert into public.notifications(recipient_id, type, ref_id, body)
    select tm.profile_id, 'join_request', _team_id,
           coalesce((select display_name from public.profiles where id = _me), 'Someone')
             || ' asked to join ' || coalesce((select name from public.teams where id = _team_id), 'your team')
    from public.team_members tm
    where tm.team_id = _team_id and tm.role in ('captain','admin')
      and tm.profile_id is not null;
  exception when others then
    raise warning 'join_request notify failed: %', sqlerrm;
  end;

  return _id;
end; $$;
revoke all on function public.request_to_join(uuid) from public;
grant execute on function public.request_to_join(uuid) to authenticated;

create or replace function public.respond_join_request(_request_id uuid, _approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare _team uuid; _requester uuid; _status public.claim_status;
begin
  select team_id, requester_id, status into _team, _requester, _status
    from public.team_join_requests where id = _request_id for update;
  if _team is null then raise exception 'request not found' using errcode='P0001'; end if;
  if not public.is_team_admin(_team) then
    raise exception 'not authorized' using errcode='P0001';
  end if;
  if _status <> 'pending' then
    raise exception 'request already handled' using errcode='P0001';
  end if;

  if _approve then
    insert into public.team_members(team_id, profile_id, role)
    values (_team, _requester, 'player')
    on conflict (team_id, profile_id) where profile_id is not null do nothing;
    update public.team_join_requests set status = 'approved' where id = _request_id;
  else
    update public.team_join_requests set status = 'rejected' where id = _request_id;
  end if;
end; $$;
revoke all on function public.respond_join_request(uuid, boolean) from public;
grant execute on function public.respond_join_request(uuid, boolean) to authenticated;
