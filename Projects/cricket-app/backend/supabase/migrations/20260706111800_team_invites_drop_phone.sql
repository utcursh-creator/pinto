-- TEAM-4 (root): the invite-by-phone path was dead code end to end - nothing
-- ever wrote invited_phone and no UI surfaced an addressed-invite inbox, while
-- the select policy kept a live branch reading private phone numbers on every
-- invite read. Team joining is invite-link/QR (multi-use tokens) + join
-- requests; remove the phantom column and its policy branch.
drop policy "team_invites_select_admin_or_invitee" on public.team_invites;
create policy "team_invites_select_admin" on public.team_invites
  for select to authenticated
  using (public.is_team_admin(team_id));

alter table public.team_invites drop column invited_phone;
