begin;
select plan(9);
-- SEC-4: table UPDATE on dm_messages is revoked; mark_thread_read only flips
-- read_at on messages the caller did NOT send.
-- SEC-3: blocks close the DM channel both ways; unknown targets are rejected;
-- creating new threads is rate-limited.
select tests.create_supabase_user('a@dm.dev');
select tests.create_supabase_user('b@dm.dev');
select tests.create_supabase_user('c@dm.dev');

select tests.authenticate_as('a@dm.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('a@dm.dev'), 'A');
select tests.authenticate_as('b@dm.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('b@dm.dev'), 'B');
select tests.authenticate_as('c@dm.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('c@dm.dev'), 'C');

-- a opens a thread with b and sends a message
select tests.authenticate_as('a@dm.dev');
select public.get_or_create_dm_thread(tests.get_supabase_uid('b@dm.dev')) as _th \gset
insert into public.dm_messages(thread_id, sender_id, body)
  values (:'_th'::uuid, tests.get_supabase_uid('a@dm.dev'), 'hello');

-- SEC-4: b cannot rewrite a's message via table UPDATE (privilege revoked)
select tests.authenticate_as('b@dm.dev');
select throws_ok(
  $$ update public.dm_messages set body = 'forged' $$,
  '42501', null, 'table UPDATE on dm_messages is revoked');

-- b marks the thread read via the RPC: a's message gets read_at
select public.mark_thread_read(:'_th'::uuid);
select isnt(
  (select read_at from public.dm_messages where thread_id = :'_th'::uuid limit 1),
  null, 'mark_thread_read stamps the other side''s message');
select is(
  (select body from public.dm_messages where thread_id = :'_th'::uuid limit 1),
  'hello', 'the message body is untouched');

-- a non-participant cannot mark the thread read
select tests.authenticate_as('c@dm.dev');
select throws_ok(
  format($$ select public.mark_thread_read(%L) $$, :'_th'::uuid),
  'P0001', 'not authorized', 'a non-participant cannot mark the thread read');

-- SEC-3: b blocks a -> a can no longer send into the existing thread
select tests.authenticate_as('b@dm.dev');
insert into public.blocked_users(blocker_id, blocked_id)
  values (tests.get_supabase_uid('b@dm.dev'), tests.get_supabase_uid('a@dm.dev'));
select tests.authenticate_as('a@dm.dev');
select throws_ok(
  format($$ insert into public.dm_messages(thread_id, sender_id, body)
            values (%L, tests.get_supabase_uid('a@dm.dev'), 'still there?') $$, :'_th'::uuid),
  '42501', null, 'a blocked sender cannot write into the existing thread');

-- ...and a cannot open a (new) channel with b either
select throws_ok(
  $$ select public.get_or_create_dm_thread(tests.get_supabase_uid('b@dm.dev')) $$,
  'P0001', 'you cannot message this user', 'a block closes thread creation');

-- an unknown target (no profile - e.g. an anonymous-only account) is rejected
select throws_ok(
  $$ select public.get_or_create_dm_thread(gen_random_uuid()) $$,
  'P0001', 'user not found', 'a target without a profile is rejected');

-- SEC-3 rate limit: the 11th NEW conversation in an hour is refused. Seed the
-- 11 target users as the superuser (RLS would block inserting others' profiles).
reset role;
select tests.create_supabase_user('t' || gs || '@rl.dev') from generate_series(1, 11) gs;
insert into public.profiles(id, display_name)
  select tests.get_supabase_uid('t' || gs || '@rl.dev'), 'T' || gs
  from generate_series(1, 11) gs;
select tests.authenticate_as('c@dm.dev');
select public.get_or_create_dm_thread(tests.get_supabase_uid('t' || gs || '@rl.dev'))
  from generate_series(1, 10) gs;
select throws_ok(
  $$ select public.get_or_create_dm_thread(tests.get_supabase_uid('t11@rl.dev')) $$,
  'P0001', 'too many new conversations - try again later',
  'the 11th new thread in an hour is rate-limited');

-- reopening an EXISTING thread is never rate-limited
select is(
  public.get_or_create_dm_thread(tests.get_supabase_uid('t1@rl.dev')),
  public.get_or_create_dm_thread(tests.get_supabase_uid('t1@rl.dev')),
  'an existing thread reopens despite the rate limit');

select * from finish();
rollback;
