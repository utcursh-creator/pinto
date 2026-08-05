-- Review #3 (LOW), finding 23: a guest claim can be approved but never
-- declined, so a bogus claim sits in the captain's inbox forever.
--
-- Approving rewrites team_members.profile_id - it hands over that guest's whole
-- batting and bowling history. So a stranger tapping "This is me" on a public
-- team page is asking for somebody's career, and the captain's only control was
-- an Approve button: no Decline, no dismiss, no swipe. The row stayed 'pending'
-- and came back on every visit to the inbox, and the requester could not
-- withdraw it either.
--
-- 'rejected' already existed in claim_status and was only ever written as a
-- SIDE EFFECT of approving a COMPETING claim, so the single-claim case - the
-- common one - had no terminal state at all.
--
-- THE TRADE, stated rather than left to be discovered: request_guest_claim
-- reopens a rejected row (its on-conflict only refuses 'approved'), so a
-- declined claimer can ask again. That is deliberate. A permanent decline would
-- mean one mis-tap locks the REAL player out of their own record for good, with
-- no way back - approve_guest_claim needs a pending row to act on. Clearing the
-- inbox is the complaint; a determined re-requester is a rate-limiting problem.
create or replace function public.decline_guest_claim(_membership_id uuid, _claimer uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  _team_id uuid;
begin
  select team_id into _team_id from public.team_members where id = _membership_id;
  if _team_id is null then
    raise exception 'membership not found' using errcode = 'P0001';
  end if;
  -- An admin of THIS team, exactly as approve_guest_claim requires. Not even
  -- the requester may decline their own: allowing it would let anyone probe
  -- which memberships exist by watching which calls succeed.
  if not public.is_team_admin(_team_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;

  update public.guest_claim_requests
     set status = 'rejected'
   where membership_id = _membership_id
     and requested_by = _claimer
     and status = 'pending';

  -- Also blocks declining twice, and declining something already approved.
  if not found then
    raise exception 'no pending claim from this user' using errcode = 'P0001';
  end if;
  -- team_members is deliberately untouched: the guest stays a guest.
end;
$function$;

revoke all on function public.decline_guest_claim(uuid, uuid) from public;
grant execute on function public.decline_guest_claim(uuid, uuid) to authenticated;
