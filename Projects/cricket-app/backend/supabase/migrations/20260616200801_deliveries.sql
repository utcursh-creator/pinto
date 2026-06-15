create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  innings_id uuid not null references public.innings(id) on delete cascade,
  seq bigint not null,
  bowler_id uuid not null references public.team_members(id),
  runs_off_bat int not null default 0,
  extra_wides int not null default 0,
  extra_no_ball_penalty int not null default 0,
  extra_byes int not null default 0,
  extra_leg_byes int not null default 0,
  extra_penalty int not null default 0,
  noball_secondary_kind public.noball_secondary_kind,
  is_legal boolean generated always as (extra_wides = 0 and extra_no_ball_penalty = 0) stored,
  wicket_type public.wicket_type,
  dismissed_player_id uuid references public.team_members(id),
  incoming_batter_id uuid references public.team_members(id),
  fielder_id uuid references public.team_members(id),
  crossed boolean,
  prevented_catch boolean,
  is_overthrow boolean not null default false,
  overthrow_crossed boolean,
  wagon_x real,
  wagon_y real,
  wagon_zone smallint,
  commentary_text text,
  striker_id uuid not null references public.team_members(id),
  non_striker_id uuid not null references public.team_members(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deliveries_not_both_wide_noball check (not (extra_wides > 0 and extra_no_ball_penalty > 0))
);
create unique index deliveries_innings_seq_uidx on public.deliveries(innings_id, seq);
alter table public.deliveries enable row level security;
grant select, insert, update, delete on public.deliveries to authenticated;
create policy "deliveries_select_authenticated" on public.deliveries
  for select to authenticated using (true);
create policy "deliveries_write_scorer" on public.deliveries
  for all to authenticated
  using (exists (select 1 from public.innings i where i.id = deliveries.innings_id and public.is_match_scorer(i.match_id)))
  with check (exists (select 1 from public.innings i where i.id = deliveries.innings_id and public.is_match_scorer(i.match_id)));
