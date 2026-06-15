begin;
select plan(5);

select tests.create_supabase_user('alice@test.dev');
select tests.create_supabase_user('bob@test.dev');

-- Alice can create her OWN profile
select tests.authenticate_as('alice@test.dev');
select lives_ok(
  $$ insert into public.profiles (id, display_name) values (tests.get_supabase_uid('alice@test.dev'), 'Alice') $$,
  'user can insert their own profile');

-- Alice CANNOT create a profile for Bob's id (WITH CHECK denies -> 42501)
select throws_ok(
  $$ insert into public.profiles (id, display_name) values (tests.get_supabase_uid('bob@test.dev'), 'FakeBob') $$,
  '42501', null,
  'user cannot insert a profile for another user');

-- Bob (after making his own profile) can READ Alice's profile (profiles public to authed users)
select tests.authenticate_as('bob@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('bob@test.dev'), 'Bob');
select is(
  (select display_name from public.profiles where id = tests.get_supabase_uid('alice@test.dev')),
  'Alice', 'authenticated user can read another profile');

-- Bob's UPDATE of Alice's row is filtered out by the RLS USING qual: 0 rows, no exception.
select lives_ok(
  $$ update public.profiles set display_name = 'hacked' where id = tests.get_supabase_uid('alice@test.dev') $$,
  'update of another user''s row runs but is a silent no-op under RLS USING');
select is(
  (select display_name from public.profiles where id = tests.get_supabase_uid('alice@test.dev')),
  'Alice', 'Alice''s display_name is unchanged after Bob''s attempted update');

select * from finish();
rollback;
