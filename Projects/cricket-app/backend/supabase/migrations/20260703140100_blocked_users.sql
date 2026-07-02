-- SEC-3 (part 1): a block list. Any user can block another; a block in EITHER
-- direction closes the DM channel between them (thread creation AND sends into
-- existing threads). Plain table + RLS - the owner manages their own rows.
create table public.blocked_users (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocked_users_not_self check (blocker_id <> blocked_id)
);

alter table public.blocked_users enable row level security;
grant select, insert, delete on public.blocked_users to authenticated;

create policy "blocked_users_select_own" on public.blocked_users
  for select to authenticated using (blocker_id = (select auth.uid()));
create policy "blocked_users_insert_own" on public.blocked_users
  for insert to authenticated with check (blocker_id = (select auth.uid()));
create policy "blocked_users_delete_own" on public.blocked_users
  for delete to authenticated using (blocker_id = (select auth.uid()));

-- True when a block exists in either direction between the caller and _other.
create or replace function public.is_blocked_between(_other uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.blocked_users
    where (blocker_id = (select auth.uid()) and blocked_id = _other)
       or (blocker_id = _other and blocked_id = (select auth.uid()))
  );
$$;
revoke all on function public.is_blocked_between(uuid) from public;
grant execute on function public.is_blocked_between(uuid) to authenticated;

-- True when the caller may write into _thread_id: they participate and no block
-- exists between them and the other participant. Used by the dm insert policy.
create or replace function public.dm_send_allowed(_thread_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select public.is_thread_participant(_thread_id)
     and not exists (
       select 1
       from public.dm_participants p
       join public.blocked_users b
         on (b.blocker_id = p.profile_id and b.blocked_id = (select auth.uid()))
         or (b.blocker_id = (select auth.uid()) and b.blocked_id = p.profile_id)
       where p.thread_id = _thread_id
         and p.profile_id <> (select auth.uid())
     );
$$;
revoke all on function public.dm_send_allowed(uuid) from public;
grant execute on function public.dm_send_allowed(uuid) to authenticated;

-- Sends into an existing thread now respect blocks too.
drop policy if exists "dm_messages_insert_participant" on public.dm_messages;
create policy "dm_messages_insert_participant" on public.dm_messages
  for insert to authenticated
  with check (public.dm_send_allowed(thread_id) and sender_id = (select auth.uid()));
