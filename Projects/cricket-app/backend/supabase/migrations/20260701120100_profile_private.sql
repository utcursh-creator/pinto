-- SEC-1 (PII leak): profiles.phone was readable by ANY authenticated user
-- (blanket `using (true)` select policy + table-wide SELECT grant, and RLS is
-- row-level not column-level). Rather than column-grant gymnastics on the
-- heavily-embedded profiles table (which breaks every reader that selects it
-- broadly - e.g. the team_invites policy), ISOLATE phone in a self-only table.
-- profiles keeps its public read grant, so name/photo embeds (rosters, discover,
-- DMs, squads) are untouched; phone simply is not on the public table to leak.
-- The owner reads it back via my_profile(); phone moves to this table below and
-- is dropped from profiles in the next migration.
create table public.profile_private (
  id    uuid primary key references public.profiles (id) on delete cascade,
  phone text
);

alter table public.profile_private enable row level security;

grant select, insert, update on public.profile_private to authenticated;

-- Self-only: a user may read/write ONLY their own private row.
create policy "profile_private_self_select" on public.profile_private
  for select to authenticated using (id = (select auth.uid()));
create policy "profile_private_self_insert" on public.profile_private
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profile_private_self_update" on public.profile_private
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Move any existing numbers over before the column is dropped.
insert into public.profile_private (id, phone)
  select id, phone from public.profiles where phone is not null;
