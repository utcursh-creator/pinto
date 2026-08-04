-- HIGH (whole-system review #2, 2026-07-28): deleting the sole captain's
-- account froze their team forever. See the inline comment for the reasoning.

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
  -- HIGH (whole-system review #2): leave_team refuses to let the last captain
  -- walk out, because a team with no captain cannot add a player, start a match,
  -- accept an invite or promote anyone - every one of those asks is_team_admin.
  -- delete_my_account had no such guard, so deleting the sole captain's account
  -- froze the team permanently.
  --
  -- Refusing the DELETION is not an option: a person must always be able to
  -- leave. So hand the captaincy on instead - to the longest-standing remaining
  -- member of each team this user captains. If there is nobody left, the team
  -- has no one to strand.
  update public.team_members tm
     set role = 'captain'
   where tm.id in (
     select distinct on (t.team_id) t.id
       from public.team_members t
      where t.left_at is null
        and t.profile_id is not null
        and t.profile_id <> _me
        and t.team_id in (
          select c.team_id from public.team_members c
           where c.profile_id = _me and c.role = 'captain' and c.left_at is null
        )
        and not exists (
          select 1 from public.team_members other
           where other.team_id = t.team_id and other.role = 'captain'
             and other.left_at is null and other.profile_id <> _me
        )
      order by t.team_id, t.created_at
   );

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
