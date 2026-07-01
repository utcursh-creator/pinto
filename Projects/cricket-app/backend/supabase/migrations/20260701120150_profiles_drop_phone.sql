-- SEC-1 (cont.): repoint the one policy that read profiles.phone at the new
-- self-only table, then drop the PII column + its index from the public table.
-- After this, `profiles` has no sensitive column, so a broad read of it can
-- leak nothing.

-- The team_invites read policy let an invitee see an invite addressed to their
-- phone; source that from profile_private now (self-row, so its own RLS allows
-- the sub-select).
drop policy "team_invites_select_admin_or_invitee" on public.team_invites;
create policy "team_invites_select_admin_or_invitee"
  on public.team_invites for select to authenticated
  using (
    public.is_team_admin(team_id)
    or invited_phone = (select phone from public.profile_private where id = (select auth.uid()))
  );

drop index if exists public.profiles_phone_idx;
alter table public.profiles drop column phone;
