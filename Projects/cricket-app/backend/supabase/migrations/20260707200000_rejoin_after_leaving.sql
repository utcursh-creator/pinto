-- CONFIRMED HIGH x3 + MEDIUM x2 (fix-run re-review 2026-07-07): the `left_at`
-- tombstone from 20260707180000_leave_team.sql made LEAVING A TEAM IRREVERSIBLE.
-- Keeping the row is right - old scorecards must still be able to name the
-- player - but every re-entry path read team_members WITHOUT filtering left_at,
-- saw the tombstone, and concluded the person was still on the team:
--
--   * accept_invite hit its "already a member" branch, returned the dead row and
--     burned no invite use, so the app said "You joined the team" and nothing
--     happened at all.
--   * request_to_join raised 'you are already on this team' - on the very screen
--     that had just offered a Request to join button.
--   * add_guest_member refused the name, so a guest who was removed could never
--     be re-added under the name their team actually calls them.
--   * transfer_scorer counted a departed player as eligible, so live scoring
--     could be handed to someone no longer on the team.
--   * set_team_member_role's last-captain guard counted DEPARTED captains.
--
-- One idea fixes all five: a departed membership is REVIVABLE. Re-entry clears
-- left_at on the EXISTING row - which preserves every match_squad, delivery and
-- innings row hanging off its id - and every "is this person on the team?"
-- question filters left_at.

CREATE OR REPLACE FUNCTION public.accept_invite(_invite_token text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  _team_id uuid; _status public.invite_status; _exp timestamptz;
  _uses int; _max int; _membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- Lock the row: concurrent redeemers serialize here (TEAM-3 TOCTOU fix).
  select team_id, status, expires_at, uses, max_uses
    into _team_id, _status, _exp, _uses, _max
    from public.team_invites
    where invite_token = _invite_token
    for update;

  if _team_id is null or _status <> 'pending' then
    raise exception 'invite not found or already used' using errcode = 'P0001';
  end if;
  if _exp < now() then
    raise exception 'invite expired' using errcode = 'P0001';
  end if;
  if _max is not null and _uses >= _max then
    raise exception 'invite fully used' using errcode = 'P0001';
  end if;

  -- Concurrency-safe join: rely on the partial unique index, not read-then-insert.
  insert into public.team_members (team_id, profile_id, role)
  values (_team_id, auth.uid(), 'player')
  on conflict (team_id, profile_id) where profile_id is not null
  do nothing
  returning id into _membership_id;

  if _membership_id is null then
    -- A row already exists. If it is a TOMBSTONE (they left this team before),
    -- revive it: same row, so their whole match history stays attached, and DO
    -- burn a use because this genuinely is someone joining. If they are simply
    -- already a member, return the row and burn nothing.
    select id into _membership_id
    from public.team_members
    where team_id = _team_id and profile_id = auth.uid();

    if exists (select 1 from public.team_members
                where id = _membership_id and left_at is not null) then
      update public.team_members set left_at = null where id = _membership_id;
      update public.team_invites set uses = uses + 1
        where invite_token = _invite_token;
    end if;
  else
    update public.team_invites set uses = uses + 1
      where invite_token = _invite_token;
  end if;

  return _membership_id;
end;
$function$;

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
      and tm.profile_id is not null;
  exception when others then
    raise warning 'join_request notify failed: %', sqlerrm;
  end;

  return _id;
end; $function$;

CREATE OR REPLACE FUNCTION public.add_guest_member(_team_id uuid, _guest_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      and left_at is null
  ) then
    raise exception 'a guest with this name is already on the team' using errcode = 'P0001';
  end if;

  insert into public.team_members (team_id, guest_name)
  values (_team_id, _name)
  returning id into _id;

  return _id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.transfer_scorer(_match_id uuid, _new_scorer_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _uid uuid := (select auth.uid());
  _m public.matches%rowtype;
  _is_caller_admin boolean;
  _is_new_eligible boolean;
begin
  if _uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;

  -- serialise against a concurrent record_ball on the same match
  perform pg_advisory_xact_lock(hashtextextended(_match_id::text, 0));

  select * into _m from public.matches where id = _match_id for update;
  if not found then raise exception 'match not found' using errcode = 'P0001'; end if;

  -- status guard
  if _m.status not in ('setup','live','innings_break') then
    raise exception 'match status % does not allow a scorer transfer', _m.status using errcode = 'P0001';
  end if;

  -- authorization: current scorer, or an admin of either participating team
  _is_caller_admin := public.is_team_admin(_m.team_a_id) or public.is_team_admin(_m.team_b_id);
  if _uid <> _m.scorer_id and not _is_caller_admin then
    raise exception 'not authorized to transfer the scorer role' using errcode = '42501';
  end if;

  -- eligibility ALWAYS checked, even on a same-scorer no-op
  _is_new_eligible := exists (
    select 1 from public.team_members tm
    where tm.profile_id = _new_scorer_id
      and tm.team_id in (_m.team_a_id, _m.team_b_id)
      and tm.left_at is null
  );
  if not _is_new_eligible then
    raise exception 'the new scorer must be a member of either team' using errcode = 'P0001';
  end if;

  -- validated no-op, else transfer
  if _m.scorer_id = _new_scorer_id then return; end if;
  update public.matches set scorer_id = _new_scorer_id where id = _match_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.set_team_member_role(_membership_id uuid, _role team_member_role)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _team uuid; _current public.team_member_role;
begin
  select team_id, role into _team, _current
    from public.team_members where id = _membership_id;
  if _team is null then raise exception 'membership not found' using errcode = 'P0001'; end if;
  if not public.is_team_admin(_team) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if _current = 'captain' and _role <> 'captain'
     and (select count(*) from public.team_members
           where team_id = _team and role = 'captain'
             and left_at is null) <= 1 then
    raise exception 'a team needs at least one captain' using errcode = 'P0001';
  end if;
  update public.team_members set role = _role where id = _membership_id;
end; $function$;
