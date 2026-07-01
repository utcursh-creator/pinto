-- SEC-1 companion: the owner's OWN profile as a jsonb object, including `phone`
-- (which now lives in the self-only profile_private table). Self-only via
-- auth.uid(); returns null when the caller has not onboarded yet. The app reads
-- its own profile (onboarding gate + edit-profile) through this, never a direct
-- table select (which no longer carries phone).
create or replace function public.my_profile()
returns jsonb
language sql
security definer
set search_path = ''
stable
as $$
  select to_jsonb(p) || jsonb_build_object('phone', pv.phone)
  from public.profiles p
  left join public.profile_private pv on pv.id = p.id
  where p.id = (select auth.uid())
$$;

revoke all on function public.my_profile() from public;
grant execute on function public.my_profile() to authenticated;
