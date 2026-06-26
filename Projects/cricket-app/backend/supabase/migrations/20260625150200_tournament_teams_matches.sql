create table public.tournament_teams (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  team_id uuid not null references public.teams(id),
  group_label text not null,
  primary key (tournament_id, team_id)
);
alter table public.tournament_teams enable row level security;
grant select, insert, update, delete on public.tournament_teams to authenticated;
grant select on public.tournament_teams to anon;
create policy "tt_select_all" on public.tournament_teams
  for select to anon, authenticated using (true);
create policy "tt_write_organizer" on public.tournament_teams
  for all to authenticated
  using (public.is_tournament_organizer(tournament_id))
  with check (public.is_tournament_organizer(tournament_id));

-- Links a normal matches row to a tournament + its stage/slot.
create table public.tournament_matches (
  match_id uuid primary key references public.matches(id) on delete cascade,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  stage public.tournament_stage not null,
  group_label text,
  bracket_slot text
);
create index tournament_matches_tid_idx on public.tournament_matches(tournament_id);
alter table public.tournament_matches enable row level security;
grant select, insert, update, delete on public.tournament_matches to authenticated;
grant select on public.tournament_matches to anon;
create policy "tm_select_all" on public.tournament_matches
  for select to anon, authenticated using (true);
create policy "tm_write_organizer" on public.tournament_matches
  for all to authenticated
  using (public.is_tournament_organizer(tournament_id))
  with check (public.is_tournament_organizer(tournament_id));
