-- LOW (fix-run re-review 2026-07-07): the notification fan-outs pick recipients
-- with `role in ('captain','admin')` and never filtered left_at, so someone who
-- LEFT a team kept receiving that team's join-request and guest-claim
-- notifications - and, because the notification row is addressed to them, could
-- read who is trying to join their old club long after leaving it. Small, but it
-- is other people's activity leaking to someone with no relationship to the team.

CREATE OR REPLACE FUNCTION public.request_to_join(_team_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _me uuid := (select auth.uid()); _id uuid;
begin
  if _me is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if exists (select 1 from public.team_members
             where team_id = _team_id and profile_id = _me
               and left_at is null) then
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
      and tm.profile_id is not null
      and tm.left_at is null;
  exception when others then
    raise warning 'join_request notify failed: %', sqlerrm;
  end;

  return _id;
end; $function$;

CREATE OR REPLACE FUNCTION public.notify_claim_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _team uuid; _who text; _guest text;
begin
  select team_id, guest_name into _team, _guest
    from public.team_members where id = NEW.membership_id;
  select display_name into _who from public.profiles where id = NEW.requested_by;
  insert into public.notifications(recipient_id, type, ref_id, body)
  select tm.profile_id, 'claim_request', NEW.membership_id,
         coalesce(_who, 'Someone') || ' says they are ' ||
         coalesce(_guest, 'a guest player') || ' - review the claim'
  from public.team_members tm
  where tm.team_id = _team and tm.role in ('captain', 'admin')
    and tm.profile_id is not null and tm.profile_id <> NEW.requested_by
    and tm.left_at is null;
  return null;
exception when others then
  raise warning 'notify_claim_request failed: %', sqlerrm; return null;
end; $function$;
