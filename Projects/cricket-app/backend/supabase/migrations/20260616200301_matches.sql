create table public.matches (
  id             uuid primary key default gen_random_uuid(),
  team_a_id      uuid not null references public.teams(id),
  team_b_id      uuid not null references public.teams(id),
  owner_id       uuid not null references public.profiles(id),
  scorer_id      uuid not null references public.profiles(id),
  overs_limit    int not null,
  balls_per_over int not null default 6,
  rules          jsonb not null default '{}'::jsonb,
  toss_winner_id uuid references public.teams(id),
  toss_decision  public.toss_decision,
  venue          text,
  city           text,
  scheduled_at   timestamptz,
  ball_type      public.ball_type,
  pitch_type     public.pitch_type,
  status         public.match_status not null default 'setup',
  result         jsonb,
  created_at     timestamptz not null default now()
);
create index matches_scorer_idx on public.matches(scorer_id);
create index matches_owner_idx  on public.matches(owner_id);
alter table public.matches enable row level security;
