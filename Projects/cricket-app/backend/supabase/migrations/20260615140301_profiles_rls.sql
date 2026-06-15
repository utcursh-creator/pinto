-- Base table privileges for the authenticated role (RLS still gates which rows).
-- Local db reset does not auto-grant to authenticated, so grant explicitly.
grant select, insert, update on public.profiles to authenticated;

-- Read: any authenticated user may read any profile (search, rosters, social).
create policy "profiles_select_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

-- Insert: only your own row.
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

-- Update: only your own row.
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);
