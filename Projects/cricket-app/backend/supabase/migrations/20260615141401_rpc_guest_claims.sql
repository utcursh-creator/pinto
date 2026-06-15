-- A user asks to claim a guest membership row.
create or replace function public.request_guest_claim(_membership_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  _is_guest boolean;
  _req_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select (guest_name is not null and profile_id is null) into _is_guest
  from public.team_members where id = _membership_id;

  if _is_guest is distinct from true then
    raise exception 'membership is not a claimable guest' using errcode = 'P0001';
  end if;

  insert into public.guest_claim_requests (membership_id, requested_by)
  values (_membership_id, auth.uid())
  on conflict (membership_id, requested_by)
    do update set status = 'pending'
    where guest_claim_requests.status <> 'approved'   -- never reopen an approved claim
  returning id into _req_id;

  if _req_id is null then
    select id into _req_id from public.guest_claim_requests
    where membership_id = _membership_id and requested_by = auth.uid();
  end if;

  return _req_id;
end;
$$;

-- A team admin approves a claim: the membership transfers to the claimer.
create or replace function public.approve_guest_claim(_membership_id uuid, _claimer uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _team_id uuid;
begin
  select team_id into _team_id from public.team_members where id = _membership_id;
  if _team_id is null then
    raise exception 'membership not found' using errcode = 'P0001';
  end if;
  if not public.is_team_admin(_team_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;

  -- Guard 1: there must be a pending claim from this user (also blocks re-approval).
  if not exists (
    select 1 from public.guest_claim_requests
    where membership_id = _membership_id and requested_by = _claimer and status = 'pending'
  ) then
    raise exception 'no pending claim for this user' using errcode = 'P0001';
  end if;

  -- Guard 2: claimer must not already be a real member of this team.
  if exists (
    select 1 from public.team_members
    where team_id = _team_id and profile_id = _claimer
  ) then
    raise exception 'claimer already a member of this team' using errcode = 'P0001';
  end if;

  update public.team_members
    set profile_id = _claimer, guest_name = null
    where id = _membership_id and profile_id is null;

  -- Guard 3: if nothing updated, the membership was already claimed.
  if not found then
    raise exception 'membership already claimed' using errcode = 'P0001';
  end if;

  update public.guest_claim_requests
    set status = 'approved'
    where membership_id = _membership_id and requested_by = _claimer;

  update public.guest_claim_requests
    set status = 'rejected'
    where membership_id = _membership_id and requested_by <> _claimer and status = 'pending';
end;
$$;

revoke all on function public.request_guest_claim(uuid) from public;
revoke all on function public.approve_guest_claim(uuid, uuid) from public;
grant execute on function public.request_guest_claim(uuid) to authenticated;
grant execute on function public.approve_guest_claim(uuid, uuid) to authenticated;
