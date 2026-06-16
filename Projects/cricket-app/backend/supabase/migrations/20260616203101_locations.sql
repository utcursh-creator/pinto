create table public.profile_locations (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  geog extensions.geography(Point,4326) not null,
  place_label text,
  updated_at timestamptz not null default now()
);
create index profile_locations_geog_idx on public.profile_locations using gist (geog);
alter table public.profile_locations enable row level security;
grant select, insert, update, delete on public.profile_locations to authenticated;
create policy "profile_locations_owner_all" on public.profile_locations for all to authenticated
  using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));

create table public.team_locations (
  team_id uuid primary key references public.teams(id) on delete cascade,
  geog extensions.geography(Point,4326) not null,
  place_label text,
  updated_at timestamptz not null default now()
);
create index team_locations_geog_idx on public.team_locations using gist (geog);
alter table public.team_locations enable row level security;
grant select, insert, update, delete on public.team_locations to authenticated;
create policy "team_locations_admin_all" on public.team_locations for all to authenticated
  using (public.is_team_admin(team_id)) with check (public.is_team_admin(team_id));
