begin;
select plan(9);
-- Review #3 (HIGH): the Discover mail and bell badges, and the DM inbox itself,
-- are fetched once per app launch and never refreshed.
--
-- Discover is the initial branch of the shell, so it stays mounted for the whole
-- session; dmInboxProvider and notificationsProvider are plain FutureProviders
-- (not autoDispose) so each resolves once and holds. There is no realtime
-- subscription of ANY kind outside the Messages screens. Aisha browses for ten
-- minutes, Rahul sends three DMs and replies to her post, and both badges stay
-- empty - and opening the inbox shows the ten-minute-old rows, because the
-- provider still holds them.
--
-- This is also review-#2's finding 40, which was DEFERRED with the note "fixing
-- it properly needs a per-user realtime topic, which is a backend design
-- change". This is that change, and it closes both.
--
-- ONE topic per user, `user:<uid>`, carrying every event that could change a
-- badge. Two producers, because they answer different questions:
--   * public.notifications - the bell. Every notification-worthy event in the
--     app already funnels through this table with a recipient_id (DMs, post
--     replies, claim requests, invites, match events).
--   * dm_messages - the mail. notify_dm_message deliberately does NOT insert a
--     second notification while an unread one exists, so the notifications
--     trigger alone would miss the 2nd and 3rd message of a burst.

select tests.create_supabase_user('a@ut.dev');
select tests.create_supabase_user('b@ut.dev');
select tests.authenticate_as('b@ut.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('b@ut.dev'),'B');
select tests.authenticate_as('a@ut.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@ut.dev'),'A');
select tests.get_supabase_uid('a@ut.dev') as _a \gset
select tests.get_supabase_uid('b@ut.dev') as _b \gset
select public.get_or_create_dm_thread(:'_b'::uuid) as _t \gset

-- COUNTING IS ELEVATED from here to test 5. The receive policy hides another
-- user's topic - which is exactly what assertions 7 and 8 below check - so the
-- observations have to be made as the owner; only the AUTHORIZATION assertions
-- are made as the users themselves.
select current_role as _seedrole \gset
set local role postgres;

-- 1-2. a DM reaches the RECIPIENT's topic, and only theirs
select count(*)::int as _before_b from realtime.messages
 where topic = 'user:' || :'_b' \gset
select count(*)::int as _before_a from realtime.messages
 where topic = 'user:' || :'_a' \gset
insert into public.dm_messages(thread_id, sender_id, body)
 values (:'_t'::uuid, :'_a'::uuid, 'are we on for Sunday?');
select is(
  (select count(*)::int from realtime.messages where topic = 'user:' || :'_b')
    - :_before_b,
  1, 'a DM puts exactly ONE event on the RECIPIENT''s user topic - the first '
     'message of a thread also writes a notification row, and firing both '
     'producers for it would wake the client twice for one arrival');
select is(
  (select count(*)::int from realtime.messages where topic = 'user:' || :'_a')
    - :_before_a,
  0, 'and nothing on the sender''s - your own message is not news to you');

-- 3. the SECOND message of a burst still fires, which is the whole reason the
--    dm_messages trigger exists alongside the notifications one: notify_dm_message
--    inserts no further notification while an unread one is sitting there.
select count(*)::int as _mid_b from realtime.messages
 where topic = 'user:' || :'_b' \gset
insert into public.dm_messages(thread_id, sender_id, body)
 values (:'_t'::uuid, :'_a'::uuid, 'ground is free at 3');
select is(
  (select count(*)::int from realtime.messages where topic = 'user:' || :'_b')
    - :_mid_b,
  1, 'the second message of a burst fires too - the badge must count it');

-- 4-5. a NON-DM notification (a reply to a post) reaches the bell the same way
select public.create_looking_for_post(
  'team_seeking_players'::public.lf_mode, 'practice_match'::public.lf_flair,
  18.52, 73.85, 'Need 2') as _p \gset
select count(*)::int as _pre_reply from realtime.messages
 where topic = 'user:' || :'_a' \gset
-- still elevated, so set the acting user for the trigger's auth.uid() reads
select set_config('request.jwt.claims',
  json_build_object('sub', :'_b', 'role', 'authenticated')::text, true);
insert into public.post_replies(post_id, author_id, body)
 values (:'_p'::uuid, :'_b'::uuid, 'I can play');
select is(
  (select count(*)::int from realtime.messages where topic = 'user:' || :'_a')
    - :_pre_reply,
  1, 'a reply to my post reaches my topic - the bell badge has a live signal '
     'for everything that funnels through notifications');
select is(
  (select count(*)::int from public.notifications
    where recipient_id = :'_a'::uuid and type = 'post_reply'),
  1, 'and the notification row itself is still written');

set local role :_seedrole;

-- 6-7. AUTHORIZATION: the topic is private, and it is mine alone.
select is(
  (select count(*)::int from pg_policies
    where schemaname = 'realtime' and tablename = 'messages'
      and qual like '%user:%'),
  1, 'there is a receive policy for the user topic');
select tests.authenticate_as('b@ut.dev');
select is(
  (select count(*)::int from realtime.messages m
    where m.topic = 'user:' || :'_a'),
  0, 'B cannot read A''s topic - a badge feed that leaked would be a preview of '
     'somebody else''s messages');

-- 8. CONTROL: A can read their own
select tests.authenticate_as('a@ut.dev');
select isnt(
  (select count(*)::int from realtime.messages m
    where m.topic = 'user:' || :'_a'),
  0, 'and A can read their own');

-- 9. CONTROL: a broadcast failure must never break the write it hangs off.
--    Every other broadcast in this codebase swallows its own errors for this
--    reason; a badge is not worth losing a message over.
select matches(
  (select pg_get_functiondef(p.oid) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'broadcast_user_event'),
  'exception\s+when\s+others',
  'the user-topic broadcast swallows its own failures');

select * from finish();
rollback;
