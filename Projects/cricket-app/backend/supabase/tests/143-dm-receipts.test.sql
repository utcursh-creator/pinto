begin;
select plan(11);
-- DM read receipts: sent / delivered / seen ticks (user request, 2026-08-05).
--
-- `read_at` already existed and drives the unread badge. Ticks need one more
-- fact - whether the message reached the other person's DEVICE - which is not
-- the same as whether they have looked at it. So:
--
--   sent      the row exists on the server (one tick)
--   delivered their app has the message (two ticks)     <- delivered_at
--   seen      they opened the thread (two coloured ticks) <- read_at
--
-- Both stamps are set BY THE RECIPIENT, never by the sender, and neither can
-- move once set: a receipt that could be re-stamped would let the tick times
-- drift backwards on a re-sync.

select tests.create_supabase_user('a@rt.dev');
select tests.create_supabase_user('b@rt.dev');
select tests.create_supabase_user('c@rt.dev');
select tests.authenticate_as('b@rt.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('b@rt.dev'),'B');
select tests.authenticate_as('c@rt.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('c@rt.dev'),'C');
select tests.authenticate_as('a@rt.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@rt.dev'),'A');

select tests.get_supabase_uid('a@rt.dev') as _a \gset
select tests.get_supabase_uid('b@rt.dev') as _b \gset
select tests.get_supabase_uid('c@rt.dev') as _c \gset
select public.get_or_create_dm_thread(:'_b'::uuid) as _t \gset

-- A sends two, B replies once
insert into public.dm_messages(thread_id, sender_id, body)
 values (:'_t'::uuid, :'_a'::uuid, 'are we on for Sunday?');
insert into public.dm_messages(thread_id, sender_id, body)
 values (:'_t'::uuid, :'_a'::uuid, 'ground is free at 3');
select tests.authenticate_as('b@rt.dev');
insert into public.dm_messages(thread_id, sender_id, body)
 values (:'_t'::uuid, :'_b'::uuid, 'checking with the lads');

-- 1. nothing is delivered until the other device says so
select tests.authenticate_as('a@rt.dev');
select is(
  (select count(*)::int from public.dm_messages
    where thread_id = :'_t'::uuid and delivered_at is not null),
  0, 'a message starts as sent only - one tick');

-- 2-4. B's app receives them
select tests.authenticate_as('b@rt.dev');
select public.mark_thread_delivered(:'_t'::uuid);
select is(
  (select count(*)::int from public.dm_messages
    where thread_id = :'_t'::uuid and sender_id = :'_a'::uuid
      and delivered_at is not null),
  2, 'both of A''s messages are delivered');
select is(
  (select count(*)::int from public.dm_messages
    where thread_id = :'_t'::uuid and sender_id = :'_b'::uuid
      and delivered_at is not null),
  0, 'B does not deliver messages to himself - a tick on your own message '
     'would mean nothing');
select is(
  (select count(*)::int from public.dm_messages
    where thread_id = :'_t'::uuid and read_at is not null),
  0, 'delivered is NOT seen. This is the whole distinction: the phone has it, '
     'the person has not looked');

-- 5. the SENDER can read the stamps - otherwise no tick could ever change
select tests.authenticate_as('a@rt.dev');
select is(
  (select count(*)::int from public.dm_messages
    where thread_id = :'_t'::uuid and sender_id = :'_a'::uuid
      and delivered_at is not null),
  2, 'and the sender can see that they were delivered');

-- 6. the stamp does not move. A re-sync calls this again on every reconnect.
select tests.authenticate_as('b@rt.dev');
select (select min(delivered_at) from public.dm_messages
         where thread_id = :'_t'::uuid and sender_id = :'_a'::uuid) as _first \gset
select public.mark_thread_delivered(:'_t'::uuid);
select is(
  (select min(delivered_at) from public.dm_messages
    where thread_id = :'_t'::uuid and sender_id = :'_a'::uuid),
  :'_first'::timestamptz,
  'calling it again does not re-stamp - the tick time would walk forward on '
  'every reconnect');

-- 7-8. B opens the thread
select public.mark_thread_read(:'_t'::uuid);
select is(
  (select count(*)::int from public.dm_messages
    where thread_id = :'_t'::uuid and sender_id = :'_a'::uuid
      and read_at is not null),
  2, 'opening the thread marks them seen');
-- a message can be read without ever having been marked delivered (the app was
-- opened straight into the thread from a notification), so read must imply it
select tests.authenticate_as('a@rt.dev');
insert into public.dm_messages(thread_id, sender_id, body)
 values (:'_t'::uuid, :'_a'::uuid, 'see you at 3');
select tests.authenticate_as('b@rt.dev');
select public.mark_thread_read(:'_t'::uuid);
select is(
  (select count(*)::int from public.dm_messages
    where thread_id = :'_t'::uuid and sender_id = :'_a'::uuid
      and delivered_at is null),
  0, 'seen implies delivered - a message read from a notification never went '
     'through the delivered path, and two ticks must not be missing under a '
     'seen one');

-- 9. CONTROL: a stranger cannot stamp anything
select tests.authenticate_as('c@rt.dev');
select throws_ok(
  format($$ select public.mark_thread_delivered(%L) $$, :'_t'),
  'P0001', 'not authorized',
  'someone outside the thread cannot fake a receipt');

-- 10. CONTROL: the sender cannot stamp their OWN messages as delivered, which
--     is the only way a tick could lie.
select tests.authenticate_as('a@rt.dev');
insert into public.dm_messages(thread_id, sender_id, body)
 values (:'_t'::uuid, :'_a'::uuid, 'one more');
select public.mark_thread_delivered(:'_t'::uuid);
select is(
  (select count(*)::int from public.dm_messages
    where thread_id = :'_t'::uuid and sender_id = :'_a'::uuid
      and delivered_at is null),
  1, 'A calling it stamps nothing of his own - the newest message is still '
     'one tick');

-- 11. the receipt reaches the sender as ONE broadcast per statement.
--     Opening a thread with fifty unread messages is one UPDATE; a row-level
--     trigger would put fifty messages on the socket to say one thing.
select tests.authenticate_as('a@rt.dev');
insert into public.dm_messages(thread_id, sender_id, body)
select :'_t'::uuid, :'_a'::uuid, 'burst ' || g from generate_series(1, 5) g;
select tests.authenticate_as('b@rt.dev');
select count(*)::int as _before from realtime.messages
 where topic = 'dm:' || :'_t' and extension = 'broadcast'
   and event = 'RECEIPT' \gset
select public.mark_thread_read(:'_t'::uuid);
select is(
  (select count(*)::int from realtime.messages
    where topic = 'dm:' || :'_t' and event = 'RECEIPT') - :_before,
  1, 'five messages read at once is ONE receipt broadcast, not five');

select * from finish();
rollback;
