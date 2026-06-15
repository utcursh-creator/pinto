-- Base table privileges for authenticated (RLS gates rows; local does not auto-grant).
grant select, insert, update, delete on public.team_members to authenticated;

-- Read: any authenticated user (rosters are public).
create policy "team_members_select_authenticated"
  on public.team_members for select to authenticated using (true);

-- Insert: only a team admin (SECURITY DEFINER RPCs bypass this; direct client inserts are gated).
create policy "team_members_insert_admin"
  on public.team_members for insert to authenticated
  with check (public.is_team_admin(team_id));

-- Update: a team admin (role changes), OR a user touching their own membership row.
create policy "team_members_update_admin_or_self"
  on public.team_members for update to authenticated
  using (public.is_team_admin(team_id) or profile_id = auth.uid())
  with check (public.is_team_admin(team_id) or profile_id = auth.uid());

-- Delete: a team admin, or a user removing themselves.
create policy "team_members_delete_admin_or_self"
  on public.team_members for delete to authenticated
  using (public.is_team_admin(team_id) or profile_id = auth.uid());
