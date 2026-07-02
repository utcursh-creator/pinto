-- SEC-8 (proper fix, reverse-engineered from CricHeroes): teams get into a
-- tournament by CONSENT, not by organizer fiat. CricHeroes' model is
-- organizer-owned placement with team opt-in via a shared invite link /
-- Tournament PIN; there is NO two-way approval queue. We mirror our team_invites
-- token primitive one level up: the organizer mints an unguessable token, a
-- DIFFERENT team's admin redeems it to drop THEIR team in - that redemption is
-- the consent. Direct-add (add_tournament_team) stays for teams the organizer
-- already admins. This table reuses the invite_status enum + the exact shape of
-- team_invites.
create table public.tournament_invites (
  id               uuid primary key default gen_random_uuid(),
  tournament_id    uuid not null references public.tournaments(id) on delete cascade,
  invite_token     text unique,
  status           public.invite_status not null default 'pending',
  created_by       uuid not null references public.profiles(id),
  created_at       timestamptz not null default now(),
  redeemed_by      uuid references public.profiles(id),
  redeemed_team_id uuid references public.teams(id)
);
create index tournament_invites_tid_idx on public.tournament_invites (tournament_id);

alter table public.tournament_invites enable row level security;
grant select, insert, update, delete on public.tournament_invites to authenticated;

-- Read: only the organizer lists/monitors the invites they minted. Redemption is
-- by RPC-with-token (join_tournament_with_token), which never needs a table read
-- - so tokens are never exposed to the invitee or to anon.
create policy "tournament_invites_select_organizer"
  on public.tournament_invites for select to authenticated
  using (public.is_tournament_organizer(tournament_id));

-- Insert/Update funnel through the SECURITY DEFINER RPCs; these are defense in depth.
create policy "tournament_invites_insert_organizer"
  on public.tournament_invites for insert to authenticated
  with check (public.is_tournament_organizer(tournament_id) and created_by = (select auth.uid()));

create policy "tournament_invites_update_organizer"
  on public.tournament_invites for update to authenticated
  using (public.is_tournament_organizer(tournament_id))
  with check (public.is_tournament_organizer(tournament_id));
