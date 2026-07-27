-- HIGH (penetration review 2026-07-07, found by 2 fronts): delete_my_account
-- ABORTS with a foreign-key violation for essentially every real user.
--
-- The "clean" branch ran `delete from auth.users`, relying on the cascade to
-- profiles. But several references are NOT cascading: teams.created_by,
-- match_squad.team_member_id, deliveries.striker_id/bowler_id/... So the moment
-- a user creates a team or appears in one squad, the delete raises and the whole
-- transaction rolls back. The user taps "Delete account" and gets a raw 500,
-- forever. That is also a Play Store / App Store rejection: account deletion
-- must actually work.
--
-- Fix: drop the two-path branch. ALWAYS anonymize. The person is erased (GDPR:
-- no name, photo, city, handle, phone, posts, messages, notifications, and the
-- login identity is destroyed and permanently banned), while opponents'
-- scorecards keep referring to an inert "Deleted user" row. Their team
-- memberships become guest rows so match history stays intact without pointing
-- at a person.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
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
         guest_name = coalesce(guest_name, 'Deleted user')
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
end; $$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
