create table public.teams (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  logo_url   text,
  city       text,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create index teams_created_by_idx on public.teams (created_by);

alter table public.teams enable row level security;
