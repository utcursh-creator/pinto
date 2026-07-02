-- MISS-4 / PROF-2: account deletion (Apple/Google reject apps without it).
-- SECURITY DEFINER as postgres, which owns the auth schema locally and holds
-- delete rights on hosted Supabase - the documented alternative to a
-- service-role Edge Function.
--
-- Two paths, because profiles.id -> auth.users cascades but matches.owner_id/
-- scorer_id -> profiles does NOT (shared scorecards must survive):
--  * no match history: delete auth.users outright - profiles cascades, and
--    posts/memberships/messages cascade off profiles in turn.
--  * has match history: ANONYMIZE - blank the profile, drop the phone row and
--    posts, scrub the auth identity (email/phone/metadata), kill sessions and
--    identities, and ban the account forever. The person is gone (GDPR), the
--    opponents' match history remains under "Deleted user".
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare _me uuid := (select auth.uid()); _has_matches boolean;
begin
  if _me is null then raise exception 'not authenticated' using errcode='28000'; end if;

  select exists (
    select 1 from public.matches where owner_id = _me or scorer_id = _me
  ) into _has_matches;

  if _has_matches then
    update public.profiles
      set display_name = 'Deleted user', photo_url = null, city = null,
          handle = null, batting_style = null, bowling_style = null,
          playing_role = null
      where id = _me;
    delete from public.profile_private where id = _me;
    delete from public.looking_for_posts where author_id = _me;
    delete from public.notifications where recipient_id = _me;
    -- scrub the login identity but keep the uuid row (profiles FK cascade
    -- would otherwise destroy the anonymized profile + break matches FKs)
    update auth.users
      set email = 'deleted-' || _me || '@deleted.invalid',
          phone = null,
          encrypted_password = null,
          raw_user_meta_data = '{}'::jsonb,
          banned_until = 'infinity'
      where id = _me;
    delete from auth.identities where user_id = _me;
    delete from auth.sessions where user_id = _me;
    delete from auth.refresh_tokens where user_id = _me::text;
  else
    delete from auth.users where id = _me;  -- cascades profiles + children
  end if;
end; $$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
