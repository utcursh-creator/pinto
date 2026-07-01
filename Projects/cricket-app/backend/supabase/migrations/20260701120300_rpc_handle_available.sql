-- PROF-1: is a handle free (case-insensitive)? Drives the live availability
-- check on the create-profile screen. SECURITY DEFINER so the check runs during
-- onboarding regardless of the caller's column grants; granted to anon too so a
-- not-yet-signed-in user can validate before creating an account.
create or replace function public.handle_available(_handle text)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select not exists (
    select 1 from public.profiles where lower(handle) = lower(_handle)
  )
$$;

revoke all on function public.handle_available(text) from public;
grant execute on function public.handle_available(text) to anon, authenticated;
