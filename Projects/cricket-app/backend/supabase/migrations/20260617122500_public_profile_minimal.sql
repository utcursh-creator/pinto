-- Sub-project 4, Task 7: anon-safe resolver for REGISTERED player names.
-- Exposes only display_name / photo / batting_style; phone / city / playing_role
-- stay authenticated-only (they live on profiles, never opened to anon).
create or replace function public.public_profile_minimal(_profile_id uuid)
returns table(id uuid, display_name text, photo_url text, batting_style public.batting_style)
language sql security definer set search_path = '' stable
as $$
  select id, display_name, photo_url, batting_style
  from public.profiles
  where id = _profile_id
$$;

revoke all on function public.public_profile_minimal(uuid) from public;
grant execute on function public.public_profile_minimal(uuid) to anon, authenticated;
