begin;
select plan(8);
-- Whole-system review #2 (2026-07-28), finding 15: the DM inbox downloads every
-- message body in every thread the user has.
--
-- The client made three round-trips - thread ids, the other participant of
-- each, then EVERY MESSAGE of all of them, body included - purely to take the
-- first as a preview and count the unread ones. A long conversation is
-- thousands of rows, re-fetched on every inbox open, every incoming message and
-- every pull-to-refresh. The thread-id list also travelled in the URL, which
-- has a length limit that grows with how many people you talk to.
--
-- The RPC returns one row per thread and no body but the preview. The
-- assertions below are the CONTRACT the screen depends on - it renders exactly
-- these five keys.

select tests.create_supabase_user('me@dm.dev');
select tests.create_supabase_user('you@dm.dev');
select tests.create_supabase_user('third@dm.dev');
select tests.authenticate_as('you@dm.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('you@dm.dev'),'You');
select tests.authenticate_as('third@dm.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('third@dm.dev'),'Third');
select tests.authenticate_as('me@dm.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('me@dm.dev'),'Me');

select tests.get_supabase_uid('me@dm.dev')    as _me \gset
select tests.get_supabase_uid('you@dm.dev')   as _you \gset
select tests.get_supabase_uid('third@dm.dev') as _third \gset

select public.get_or_create_dm_thread(:'_you'::uuid)   as _t1 \gset
select public.get_or_create_dm_thread(:'_third'::uuid) as _t2 \gset

set local role postgres;
-- thread 1: a long conversation, last word from THEM and unread
insert into public.dm_messages(thread_id, sender_id, body, created_at)
select :'_t1'::uuid,
       case when g % 2 = 0 then :'_me'::uuid else :'_you'::uuid end,
       'msg ' || g, now() - ((100 - g) || ' minutes')::interval
from generate_series(1, 40) g;
-- three of theirs are unread
update public.dm_messages set read_at = now()
 where thread_id = :'_t1'::uuid and sender_id = :'_you'::uuid
   and id not in (select id from public.dm_messages
                   where thread_id = :'_t1'::uuid and sender_id = :'_you'::uuid
                   order by created_at desc limit 3);
-- thread 2: one message, from me, so nothing unread
insert into public.dm_messages(thread_id, sender_id, body, created_at)
values (:'_t2'::uuid, :'_me'::uuid, 'only mine', now() - interval '1 day');
set local role authenticated;

select public.dm_inbox() as _inbox \gset

-- 1-2. one row per thread, most recent first
select is(jsonb_array_length(public.dm_inbox()), 2,
  'one row per thread, not one per message');
select is(
  (public.dm_inbox()->0->>'thread_id'), :'_t1',
  'the most recently active conversation comes first');

-- 3-5. the five keys the screen renders
select is((public.dm_inbox()->0->>'preview'), 'msg 40',
  'the preview is the LAST message, which is all the body the inbox needs');
select is((public.dm_inbox()->0->'other'->>'display_name'), 'You',
  'and it names the other participant');
select is((public.dm_inbox()->0->>'unread')::int, 3,
  'unread counts only THEIR messages that I have not read');

-- 6. my own messages are never unread to me
select is((public.dm_inbox()->1->>'unread')::int, 0,
  'a thread where only I have spoken has nothing unread');

-- 7. CONTROL: it is scoped to the caller. A leak here would be worse than the
--    performance problem being fixed.
select tests.authenticate_as('third@dm.dev');
select is(jsonb_array_length(public.dm_inbox()), 1,
  'another user sees only their own thread');
select is(
  (public.dm_inbox()->0->'other'->>'display_name'), 'Me',
  'and the other side of it is me, not the stranger in my other thread');

select * from finish();
rollback;
