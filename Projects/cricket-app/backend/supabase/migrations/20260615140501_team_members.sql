create table public.team_members (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams (id) on delete cascade,
  profile_id uuid references public.profiles (id) on delete cascade,
  guest_name text,
  role       public.team_member_role not null default 'player',
  created_at timestamptz not null default now(),
  constraint team_members_profile_xor_guest check (
    (profile_id is not null and guest_name is null) or
    (profile_id is null and guest_name is not null)
  )
);

-- A real profile can appear at most once per team. (Partial: guests are exempt.)
create unique index team_members_unique_profile
  on public.team_members (team_id, profile_id)
  where profile_id is not null;

create index team_members_team_idx    on public.team_members (team_id);
create index team_members_profile_idx on public.team_members (profile_id);

alter table public.team_members enable row level security;
