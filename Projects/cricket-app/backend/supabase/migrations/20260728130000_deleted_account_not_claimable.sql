-- CRITICAL (whole-system review #2, 2026-07-28): deleting your account handed
-- your identity to whoever asked for it next.
--
-- delete_my_account detaches each membership - profile_id = null, guest_name =
-- 'Deleted user' - so historical scorecards keep naming a row rather than a
-- person. That instinct is right. But "profile_id is null AND guest_name is not
-- null" is EXACTLY request_guest_claim's definition of a claimable guest, so any
-- stranger could claim the departed person's membership, and once a captain
-- approved it they owned that person's innings, wickets and career record on the
-- team permanently.
--
-- The one thing that must not happen when someone asks to be forgotten is
-- somebody else inheriting them.
--
-- Two changes:
--   1. a `claimable` flag, set FALSE on the rows a deleted account leaves behind
--      (an ordinary guest stays claimable - that feature is the whole point of
--      guest rows)
--   2. delete_my_account also stamps left_at, because deleting your account is
--      also leaving every team: the rows exist for history, not for the roster.

alter table public.team_members
  add column if not exists claimable boolean not null default true;

comment on column public.team_members.claimable is
  'False for rows left behind by a deleted account. Such a row is kept only so '
  'historical scorecards render; nobody may claim it as their own identity.';

CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _me uuid := (select auth.uid());
begin
  if _me is null then raise exception 'not authenticated' using errcode='28000'; end if;

  -- 1. erase the person from the public surface
  update public.profiles
    set display_name = 'Deleted user', photo_url = null, city = null,
        handle = null, batting_style = null, bowling_style = null,
        playing_role = null
    where id = _me;

  delete from public.profile_private where id = _me;
  delete from public.looking_for_posts where author_id = _me;
  delete from public.notifications where recipient_id = _me;
  delete from public.blocked_users where blocker_id = _me or blocked_id = _me;
  delete from public.profile_locations where profile_id = _me;
  delete from public.team_join_requests where requester_id = _me;

  -- 2. detach their playing identity WITHOUT destroying match history: the
  --    membership rows survive as guests, so squads/deliveries keep resolving.
  update public.team_members
     set profile_id = null,
         guest_name = coalesce(guest_name, 'Deleted user'),
         -- nobody inherits a deleted person's cricket
         claimable = false,
         -- deleting your account is also leaving every team; the row survives
         -- for the scorecard, not for the roster
         left_at = coalesce(left_at, now())
   where profile_id = _me;

  -- 3. destroy the login. The profiles row is deliberately kept (deleting
  --    auth.users cascades to profiles, which would break the non-cascading
  --    references above) and permanently banned so it can never be signed into.
  update auth.users
    set email = 'deleted-' || _me || '@deleted.invalid',
        phone = null,
        encrypted_password = null,
        raw_user_meta_data = '{}'::jsonb,
        raw_app_meta_data = '{}'::jsonb,
        banned_until = 'infinity'
    where id = _me;
  delete from auth.identities where user_id = _me;
  delete from auth.sessions where user_id = _me;
  delete from auth.refresh_tokens where user_id = _me::text;
end; $function$;

CREATE OR REPLACE FUNCTION public.request_guest_claim(_membership_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  _is_guest boolean;
  _req_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- `claimable` is the load-bearing part: a row abandoned by a deleted account
  -- looks identical to an ordinary guest without it.
  select (guest_name is not null and profile_id is null and claimable) into _is_guest
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
$function$;
