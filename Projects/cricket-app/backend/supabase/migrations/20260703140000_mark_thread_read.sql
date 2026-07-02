-- SEC-4: the dm_messages UPDATE policy was scoped only to thread participation,
-- so a participant could rewrite/forge ANY message in the thread - the other
-- person's body, sender_id, created_at. Revoke table UPDATE entirely and route
-- the single legitimate mutation (marking the other side's messages read)
-- through a SECURITY DEFINER RPC that touches only read_at on messages the
-- caller did NOT send. Enables DM-4 (unread state).
drop policy if exists "dm_messages_update_read" on public.dm_messages;
revoke update on public.dm_messages from authenticated;

create or replace function public.mark_thread_read(_thread_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_thread_participant(_thread_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  update public.dm_messages
    set read_at = now()
    where thread_id = _thread_id
      and sender_id <> (select auth.uid())
      and read_at is null;
end; $$;
revoke all on function public.mark_thread_read(uuid) from public;
grant execute on function public.mark_thread_read(uuid) to authenticated;
