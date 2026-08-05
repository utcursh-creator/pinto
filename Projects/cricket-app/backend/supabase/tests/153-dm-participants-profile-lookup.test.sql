begin;
select plan(4);
-- Review #3 (MEDIUM), finding 13: dm_inbox() filters dm_participants on
-- profile_id alone, and the only index mentioning that column is the primary
-- key btree(thread_id, profile_id) - where it is the SECOND column, useless for
-- a lookup that does not also know the thread. So every inbox load reads the
-- WHOLE table.
--
-- MEASURED here before changing anything, with 200 decoy profiles -> 19,900
-- threads -> 39,814 dm_participants rows:
--   before: Seq Scan, 294 shared buffers, 39,615 rows removed by filter, 0.806ms
--   after : Index Only Scan, 5 buffers, 0.021ms
-- ~59x fewer buffers, and the important part is the shape: the cost scales with
-- the number of conversations ON THE PLATFORM, not with the number this user
-- has. A user with zero messages pays the same full pass as anyone else.
--
-- Who pays it: everyone who opens Messages. dm_inbox_screen invalidates
-- dmInboxProvider from inside the per-thread realtime listener, so the RPC
-- re-runs on EVERY incoming message in ANY visible thread, plus on every
-- pull-to-refresh and after every markThreadRead.
--
-- This is verbatim the argument 20260804140000_scale_indexes.sql already made
-- for match_squad ("the only index mentioning that column is the composite
-- UNIQUE ... where it is the SECOND column"). That migration added
-- match_squad_member_idx and left dm_participants alone; dm_inbox() postdates
-- it and concentrated three client round-trips into this one predicate.
--
-- THIS FILE IS A STRUCTURAL PIN, not a benchmark. A timing assertion would be
-- flaky and a 40k-row fixture would make the suite crawl; the measurement above
-- is recorded in the commit. What is asserted here is the thing that can
-- silently regress: the index existing, on the right column, in first position.

select is(
  (select count(*)::int from pg_index i
     join pg_class c on c.oid = i.indrelid
     join pg_attribute a on a.attrelid = c.oid and a.attnum = i.indkey[0]
    where c.relname = 'dm_participants' and a.attname = 'profile_id'),
  1, 'dm_participants has an index whose FIRST column is profile_id - the '
     'composite PK does not count, profile_id is second there and a lookup '
     'that does not know the thread cannot use it');

-- 2. the PK is still there. An index for the new access path must not have
--    been swapped in for the one that enforces one row per (thread, person).
select is(
  (select count(*)::int from pg_indexes
    where tablename = 'dm_participants' and indexdef like '%UNIQUE%'),
  1, 'and the primary key still enforces one row per participant per thread');

-- 3-4. Behaviour is unchanged. An index is invisible to callers, which is
--      exactly why it needs a test that would notice if the migration had
--      quietly changed anything else about the table.
select tests.create_supabase_user('a@dmi.dev');
select tests.create_supabase_user('b@dmi.dev');
select tests.authenticate_as('b@dmi.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('b@dmi.dev'),'B');
select tests.authenticate_as('a@dmi.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@dmi.dev'),'A');
select public.get_or_create_dm_thread(tests.get_supabase_uid('b@dmi.dev')) as _t \gset
insert into public.dm_messages(thread_id, sender_id, body)
  values (:'_t'::uuid, tests.get_supabase_uid('a@dmi.dev'), 'still works');

select is(
  jsonb_array_length(to_jsonb(public.dm_inbox())),
  1, 'dm_inbox still returns the thread');
select tests.authenticate_as('b@dmi.dev');
select is(
  (select (t->>'unread')::int from jsonb_array_elements(to_jsonb(public.dm_inbox())) t),
  1, 'and the recipient still sees it unread - the count the badge is drawn '
     'from is unchanged');

select * from finish();
rollback;
