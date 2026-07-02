-- MISS-2: the in-app notifications inbox. Without it the matchmaking loop dies
-- silently - nobody learns that someone replied/claimed/joined/messaged or that
-- a match went live. Rows are written by SECURITY DEFINER triggers; the
-- recipient reads + marks their own rows.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,   -- post_reply | dm | claim_request | invite_accepted | match_live
  ref_id uuid,          -- the post / thread / membership / match it points at
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_recipient_idx
  on public.notifications(recipient_id, created_at desc);

alter table public.notifications enable row level security;
grant select, update, delete on public.notifications to authenticated;

-- The recipient owns their rows outright: read, mark read, dismiss.
create policy "notifications_select_own" on public.notifications
  for select to authenticated using (recipient_id = (select auth.uid()));
create policy "notifications_update_own" on public.notifications
  for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));
create policy "notifications_delete_own" on public.notifications
  for delete to authenticated using (recipient_id = (select auth.uid()));
