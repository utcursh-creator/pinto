create table public.post_replies (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.looking_for_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
create index post_replies_post_idx on public.post_replies(post_id);
alter table public.post_replies enable row level security;
grant select, insert, delete on public.post_replies to authenticated;
create policy "post_replies_select_authenticated" on public.post_replies for select to authenticated using (true);
create policy "post_replies_insert_own" on public.post_replies for insert to authenticated
  with check (author_id = (select auth.uid()));
create policy "post_replies_delete_own" on public.post_replies for delete to authenticated
  using (author_id = (select auth.uid()));
