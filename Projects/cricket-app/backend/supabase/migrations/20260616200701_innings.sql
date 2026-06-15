create table public.innings (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  innings_number int not null,
  batting_team_id uuid not null references public.teams(id),
  bowling_team_id uuid not null references public.teams(id),
  opening_striker_id uuid not null references public.team_members(id),
  opening_non_striker_id uuid not null references public.team_members(id),
  overs_limit int,
  revised_overs int,
  target int,
  status public.innings_status not null default 'in_progress',
  created_at timestamptz not null default now(),
  unique(match_id, innings_number)
);
create index innings_match_idx on public.innings(match_id);
alter table public.innings enable row level security;
grant select, insert, update, delete on public.innings to authenticated;
create policy "innings_select_authenticated" on public.innings
  for select to authenticated using (true);
create policy "innings_write_scorer" on public.innings
  for all to authenticated
  using (public.is_match_scorer(match_id)) with check (public.is_match_scorer(match_id));
