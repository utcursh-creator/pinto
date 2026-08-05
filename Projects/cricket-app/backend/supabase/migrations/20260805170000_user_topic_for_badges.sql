-- Review #3 (HIGH): the Discover mail and bell badges, and the DM inbox itself,
-- are fetched once per app launch and never refreshed.
--
-- Discover is the initial branch of the shell so it stays mounted all session;
-- dmInboxProvider and notificationsProvider are plain FutureProviders, so each
-- resolves once and holds for the process lifetime. There is no realtime
-- subscription of any kind outside the Messages screens. Ten minutes and three
-- DMs later both badges are still empty, and opening the inbox shows the
-- ten-minute-old rows.
--
-- This is ALSO review-#2's finding 40, deferred at the time with the note that
-- "fixing it properly needs a per-user realtime topic, which is a backend design
-- change". This is that change; it closes both, and it replaces the inbox's
-- one-channel-per-visible-thread with a single join per user.
--
-- ONE topic per user - `user:<uid>` - and two producers, because they answer
-- different questions:
--   * notifications: the bell. Every notification-worthy event already funnels
--     through that table with a recipient_id (DMs, replies, claims, invites,
--     match events), so one trigger covers the lot.
--   * dm_messages: the mail. notify_dm_message deliberately does NOT insert a
--     second notification while an unread one is already sitting there, so the
--     notifications trigger alone would miss the 2nd and 3rd message of a burst
--     - exactly the case in the finding.
create or replace function public.broadcast_user_event(_user_id uuid, _kind text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if _user_id is null then return; end if;
  perform realtime.send(
    jsonb_build_object('kind', _kind), 'USER', 'user:' || _user_id::text, true);
exception when others then
  -- a badge is never worth losing the write it hangs off; every other broadcast
  -- in this codebase swallows its own errors for the same reason
  raise warning 'broadcast_user_event failed: %', sqlerrm;
end; $function$;

create or replace function public.broadcast_notification_to_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- 'dm' is already covered, per MESSAGE, by the dm_messages trigger below.
  -- Without this skip the first message of a thread (the one that also writes a
  -- notification row) would wake the client twice for a single arrival.
  if NEW.type = 'dm' then return null; end if;
  perform public.broadcast_user_event(NEW.recipient_id, 'notification');
  return null;
end; $function$;

drop trigger if exists notifications_user_broadcast on public.notifications;
create trigger notifications_user_broadcast
  after insert on public.notifications
  for each row execute function public.broadcast_notification_to_user();

-- the mail half: every message, to the OTHER participant only
create or replace function public.broadcast_dm_to_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare _other uuid;
begin
  select p.profile_id into _other
    from public.dm_participants p
   where p.thread_id = NEW.thread_id and p.profile_id <> NEW.sender_id
   limit 1;
  perform public.broadcast_user_event(_other, 'dm');
  return null;
end; $function$;

drop trigger if exists dm_messages_user_broadcast on public.dm_messages;
create trigger dm_messages_user_broadcast
  after insert on public.dm_messages
  for each row execute function public.broadcast_dm_to_user();

-- The topic is private and personal: only the user it is named after may read
-- it. A badge feed that leaked would be a preview of somebody else's messages.
drop policy if exists user_broadcast_receive on realtime.messages;
create policy user_broadcast_receive on realtime.messages for select to authenticated
  using (
    extension = 'broadcast'
    and realtime.topic() like 'user:%'
    and split_part(realtime.topic(), ':', 2) = (select auth.uid())::text
  );

revoke all on function public.broadcast_user_event(uuid, text) from public;
