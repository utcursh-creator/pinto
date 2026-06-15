create table public.team_invites (
  id            uuid primary key default gen_random_uuid(),
  team_id       uuid not null references public.teams (id) on delete cascade,
  invited_phone text,
  invite_token  text unique,
  status        public.invite_status not null default 'pending',
  created_by    uuid not null references public.profiles (id),
  created_at    timestamptz not null default now()
);

create index team_invites_team_idx on public.team_invites (team_id);

alter table public.team_invites enable row level security;

grant select, insert, update, delete on public.team_invites to authenticated;

-- Read: team admins see their team's invites; an invited user can see an invite to their phone.
create policy "team_invites_select_admin_or_invitee"
  on public.team_invites for select to authenticated
  using (
    public.is_team_admin(team_id)
    or invited_phone = (select phone from public.profiles where id = auth.uid())
  );

-- Insert: only a team admin, recording themselves as creator.
create policy "team_invites_insert_admin"
  on public.team_invites for insert to authenticated
  with check (public.is_team_admin(team_id) and created_by = auth.uid());

-- Update: a team admin (e.g. expire/cancel). Invitee acceptance goes through the RPC.
create policy "team_invites_update_admin"
  on public.team_invites for update to authenticated
  using (public.is_team_admin(team_id)) with check (public.is_team_admin(team_id));
