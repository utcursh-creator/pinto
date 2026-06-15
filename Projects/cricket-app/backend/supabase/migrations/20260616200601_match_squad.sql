create table public.match_squad (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  team_id uuid not null references public.teams(id),
  team_member_id uuid not null references public.team_members(id),
  batting_order int,
  is_captain boolean not null default false,
  is_wicket_keeper boolean not null default false,
  is_substitute boolean not null default false,
  created_at timestamptz not null default now(),
  unique(match_id, team_member_id)
);
create index match_squad_match_idx on public.match_squad(match_id);
alter table public.match_squad enable row level security;
grant select, insert, update, delete on public.match_squad to authenticated;
create policy "match_squad_select_authenticated" on public.match_squad
  for select to authenticated using (true);
create policy "match_squad_write_scorer" on public.match_squad
  for all to authenticated
  using (public.is_match_scorer(match_id)) with check (public.is_match_scorer(match_id));
