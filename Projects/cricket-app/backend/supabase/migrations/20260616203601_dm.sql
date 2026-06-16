create table public.dm_threads (
  id uuid primary key default gen_random_uuid(),
  user_lo uuid not null references public.profiles(id) on delete cascade,
  user_hi uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint dm_threads_ordered check (user_lo < user_hi)
);
create unique index dm_threads_pair_uniq on public.dm_threads(user_lo, user_hi);

create table public.dm_participants (
  thread_id uuid not null references public.dm_threads(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  primary key (thread_id, profile_id)
);

create table public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.dm_threads(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index dm_messages_thread_idx on public.dm_messages(thread_id, created_at);

create or replace function public.is_thread_participant(_thread_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.dm_participants where thread_id = _thread_id and profile_id = (select auth.uid()));
$$;
revoke all on function public.is_thread_participant(uuid) from public;
grant execute on function public.is_thread_participant(uuid) to authenticated;

alter table public.dm_threads enable row level security;
alter table public.dm_participants enable row level security;
alter table public.dm_messages enable row level security;
grant select, insert on public.dm_threads to authenticated;
grant select, insert on public.dm_participants to authenticated;
grant select, insert, update on public.dm_messages to authenticated;

create policy "dm_threads_select_participant" on public.dm_threads for select to authenticated
  using (public.is_thread_participant(id));
create policy "dm_participants_select" on public.dm_participants for select to authenticated
  using (profile_id = (select auth.uid()) or public.is_thread_participant(thread_id));
create policy "dm_messages_select_participant" on public.dm_messages for select to authenticated
  using (public.is_thread_participant(thread_id));
create policy "dm_messages_insert_participant" on public.dm_messages for insert to authenticated
  with check (public.is_thread_participant(thread_id) and sender_id = (select auth.uid()));
create policy "dm_messages_update_read" on public.dm_messages for update to authenticated
  using (public.is_thread_participant(thread_id)) with check (public.is_thread_participant(thread_id));
