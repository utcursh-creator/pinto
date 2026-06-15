create table public.guest_claim_requests (
  id            uuid primary key default gen_random_uuid(),
  membership_id uuid not null references public.team_members (id) on delete cascade,
  requested_by  uuid not null references public.profiles (id) on delete cascade,
  status        public.claim_status not null default 'pending',
  created_at    timestamptz not null default now(),
  unique (membership_id, requested_by)
);

alter table public.guest_claim_requests enable row level security;

grant select on public.guest_claim_requests to authenticated;

-- Read: the requester, or an admin of the membership's team. (Writes happen via SECURITY DEFINER RPCs.)
create policy "guest_claims_select_requester_or_admin"
  on public.guest_claim_requests for select to authenticated
  using (
    requested_by = auth.uid()
    or public.is_team_admin((select team_id from public.team_members where id = membership_id))
  );
