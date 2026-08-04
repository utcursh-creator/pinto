-- Whole-system review #2 (2026-07-28): a player who leaves a team can never
-- rejoin it through a join request.
--
-- leave_team is a SOFT delete - it stamps left_at so the player's match history
-- stays attached to the same membership row. respond_join_request then did
--
--   insert into public.team_members ...
--   on conflict (team_id, profile_id) where profile_id is not null do nothing
--
-- and that row still exists, so the insert quietly did NOTHING - while the
-- request was marked 'approved' regardless. The captain is told it worked. The
-- player is still off the roster, with no indication why.
--
-- Worse, the request is now consumed, so raising a fresh one fails in exactly
-- the same way: the lockout is PERMANENT. Falling out with a club and coming
-- back the following season is an entirely ordinary thing to do in club
-- cricket, and the app made it impossible.
--
-- accept_invite already revives the tombstone deliberately, with a comment
-- explaining why - so this was a gap, not a design decision.
create or replace function public.respond_join_request(_request_id uuid, _approve boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
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
    on conflict (team_id, profile_id) where profile_id is not null
    -- Revive the SAME row rather than creating a second one, so every innings
    -- they ever played for this club stays theirs.
    --
    -- The WHERE matters: it confines this to genuine tombstones. Without it an
    -- approval would rewrite the role of somebody who is already an active
    -- member - silently demoting a captain to player.
    do update set left_at = null, role = 'player'
    where public.team_members.left_at is not null;
    update public.team_join_requests set status = 'approved' where id = _request_id;
  else
    update public.team_join_requests set status = 'rejected' where id = _request_id;
  end if;
end; $function$;
