begin;
select plan(4);
select tests.create_supabase_user('a@m.dev'); select tests.create_supabase_user('b@m.dev'); select tests.create_supabase_user('c@m.dev');
select tests.authenticate_as('a@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
select tests.authenticate_as('b@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('b@m.dev'),'B');
select tests.authenticate_as('c@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('c@m.dev'),'C');

select tests.authenticate_as('a@m.dev');
select public.get_or_create_dm_thread(tests.get_supabase_uid('b@m.dev')) as _t \gset
-- idempotent: same pair returns the same thread
select is(public.get_or_create_dm_thread(tests.get_supabase_uid('b@m.dev'))::text, (:'_t'::uuid)::text, 'thread creation is idempotent for the same pair');
-- A (participant) can send
-- format(), not `(select id from public.dm_threads limit 1)`: that picked
-- whatever thread the local DB happened to hold, so a device-journey run left
-- these two assertions pointing at somebody else's conversation.
select lives_ok(format($$ insert into public.dm_messages(thread_id, sender_id, body) values (%L, tests.get_supabase_uid('a@m.dev'), 'hi') $$, :'_t'), 'participant can send');
-- C (outsider) cannot read the thread's messages
select tests.authenticate_as('c@m.dev');
select is((select count(*)::int from public.dm_messages where thread_id = :'_t'::uuid), 0, 'non-participant cannot read messages');
-- C cannot send into the thread (subquery, not :var, inside the dollar-quoted string)
select throws_ok(format($$ insert into public.dm_messages(thread_id, sender_id, body) values (%L, tests.get_supabase_uid('c@m.dev'), 'intrude') $$, :'_t'), '42501', null, 'non-participant cannot send');
select * from finish();
rollback;
