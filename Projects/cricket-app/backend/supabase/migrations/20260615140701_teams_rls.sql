-- Base table privileges for authenticated (RLS gates rows; local does not auto-grant).
grant select, insert, update, delete on public.teams to authenticated;

-- Read: any authenticated user.
create policy "teams_select_authenticated"
  on public.teams for select to authenticated using (true);

-- Insert: allowed only when created_by is yourself (the create_team RPC uses this identity).
create policy "teams_insert_own"
  on public.teams for insert to authenticated
  with check (auth.uid() = created_by);

-- Update/Delete: only captain/admin of the team.
create policy "teams_update_admin"
  on public.teams for update to authenticated
  using (public.is_team_admin(id)) with check (public.is_team_admin(id));

create policy "teams_delete_admin"
  on public.teams for delete to authenticated
  using (public.is_team_admin(id));
