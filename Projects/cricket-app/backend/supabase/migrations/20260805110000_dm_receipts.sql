-- DM read receipts: sent / delivered / seen (user request, 2026-08-05).
--
-- `read_at` already told us whether the recipient had OPENED the thread. Ticks
-- need the step before that - whether the message reached their device at all -
-- so a sender can tell "not connected" from "read it and said nothing":
--
--   sent      the row exists on the server            one tick
--   delivered their app has it (delivered_at)         two ticks
--   seen      they opened the thread (read_at)        two coloured ticks
--
-- Both stamps are written BY THE RECIPIENT through a SECURITY DEFINER RPC, and
-- neither can move once set: UPDATE on dm_messages is not granted to clients
-- (SEC-4), so a sender cannot mark their own message delivered, and a re-sync
-- calling this on every reconnect cannot walk the tick time forward.
alter table public.dm_messages
  add column if not exists delivered_at timestamptz;

comment on column public.dm_messages.delivered_at is
  'Set by the RECIPIENT''s client when the message reaches their device. '
  'Distinct from read_at, which means they opened the thread.';

-- The recipient's app calls this when a message arrives over realtime, or when
-- it loads a thread it is not currently showing.
create or replace function public.mark_thread_delivered(_thread_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_thread_participant(_thread_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  update public.dm_messages
     set delivered_at = now()
   where thread_id = _thread_id
     and sender_id <> (select auth.uid())
     and delivered_at is null;
end; $function$;

revoke all on function public.mark_thread_delivered(uuid) from public;
grant execute on function public.mark_thread_delivered(uuid) to authenticated;

-- Seen implies delivered. A message opened straight from a push notification
-- never went through the delivered path, and two ticks must not be missing
-- underneath a seen one.
create or replace function public.mark_thread_read(_thread_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_thread_participant(_thread_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  update public.dm_messages
     set read_at = now(),
         delivered_at = coalesce(delivered_at, now())
   where thread_id = _thread_id
     and sender_id <> (select auth.uid())
     and read_at is null;
end; $function$;

-- ONE receipt broadcast per statement, not one per row.
--
-- Opening a thread with fifty unread messages is a single UPDATE; a row-level
-- broadcast trigger would put fifty messages on the socket for what is one fact
-- ("this thread's receipts moved"). The sender's client re-reads the stamps of
-- its own recent messages when it hears this.
create or replace function public.broadcast_dm_receipt()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare _t uuid;
begin
  for _t in select distinct thread_id from changed loop
    perform realtime.send(
      jsonb_build_object('thread_id', _t), 'RECEIPT', 'dm:' || _t::text, true);
  end loop;
  return null;
exception when others then
  -- a lost tick must never fail the read itself
  raise warning 'broadcast_dm_receipt failed: %', sqlerrm;
  return null;
end; $function$;

drop trigger if exists dm_messages_receipt_broadcast on public.dm_messages;
create trigger dm_messages_receipt_broadcast
  after update on public.dm_messages
  referencing new table as changed
  for each statement execute function public.broadcast_dm_receipt();
