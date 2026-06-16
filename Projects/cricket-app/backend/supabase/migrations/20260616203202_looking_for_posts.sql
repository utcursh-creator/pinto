create table public.looking_for_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  team_id uuid references public.teams(id) on delete cascade,
  mode public.lf_mode not null,
  title text,
  description text,
  geog extensions.geography(Point,4326) not null,
  place_label text,
  match_at timestamptz,
  overs int,
  skill public.skill_level,
  slots_needed int,
  status public.lf_status not null default 'open',
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
create index looking_for_posts_geog_idx on public.looking_for_posts using gist (geog);
create index looking_for_posts_author_idx on public.looking_for_posts(author_id);
create index looking_for_posts_team_idx on public.looking_for_posts(team_id);
alter table public.looking_for_posts enable row level security;
grant select, insert, update, delete on public.looking_for_posts to authenticated;
create policy "posts_select_authenticated" on public.looking_for_posts for select to authenticated using (true);
create policy "posts_insert_author" on public.looking_for_posts for insert to authenticated
  with check (author_id = (select auth.uid()) and (team_id is null or public.is_team_admin(team_id)));
create policy "posts_update_author" on public.looking_for_posts for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));
create policy "posts_delete_author" on public.looking_for_posts for delete to authenticated
  using (author_id = (select auth.uid()));
