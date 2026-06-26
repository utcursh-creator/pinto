create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  organizer_id uuid not null references public.profiles(id),
  overs_limit int not null,
  balls_per_over int not null default 6,
  ball_type public.ball_type,
  group_count int not null,
  qualifiers_per_group int not null,
  status public.tournament_status not null default 'setup',
  champion_team_id uuid references public.teams(id),
  city text,
  venue text,
  starts_on date,
  ends_on date,
  created_at timestamptz not null default now()
);
create index tournaments_organizer_idx on public.tournaments(organizer_id);
alter table public.tournaments enable row level security;
grant select, insert, update, delete on public.tournaments to authenticated;
grant select on public.tournaments to anon;
create policy "tournaments_select_all" on public.tournaments
  for select to anon, authenticated using (true);
create policy "tournaments_write_organizer" on public.tournaments
  for all to authenticated
  using (organizer_id = (select auth.uid())) with check (organizer_id = (select auth.uid()));

-- Organizer check used to gate the tournament RPCs + child-table RLS.
create or replace function public.is_tournament_organizer(_t uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.tournaments
    where id = _t and organizer_id = (select auth.uid())
  );
$$;
