begin;
select plan(11);

-- ── PROF-1 / MISS-5: unique handle column ───────────────────────────────────
select has_column('public', 'profiles', 'handle', 'profiles has a handle column');
select col_type_is('public', 'profiles', 'handle', 'text', 'handle is text');

-- ── SEC-1: phone is OFF the public profiles table, isolated in profile_private ─
select hasnt_column('public', 'profiles', 'phone', 'profiles no longer exposes phone');
select has_table('public', 'profile_private', 'profile_private table exists');

-- ── data setup ──────────────────────────────────────────────────────────────
select tests.create_supabase_user('alice@test.dev');
select tests.create_supabase_user('bob@test.dev');

select tests.authenticate_as('alice@test.dev');
insert into public.profiles(id, display_name, handle)
  values (tests.get_supabase_uid('alice@test.dev'), 'Alice', 'alice_c');
insert into public.profile_private(id, phone)
  values (tests.get_supabase_uid('alice@test.dev'), '+911111111111');

-- ── SEC-1: the owner reads their OWN phone via my_profile() ──────────────────
select is( (public.my_profile()->>'phone'), '+911111111111', 'my_profile() returns the owner''s phone');
select is( (public.my_profile()->>'display_name'), 'Alice',   'my_profile() returns the owner''s display_name');

-- ── PROF-1: handle_available() (case-insensitive) ───────────────────────────
select is( public.handle_available('brand_new'), true,  'handle_available true for an unused handle');
select is( public.handle_available('ALICE_C'),   false, 'handle_available false (case-insensitive) for a taken handle');

-- ── SEC-1: another authenticated user CANNOT read Alice''s phone row ──────────
select tests.authenticate_as('bob@test.dev');
insert into public.profiles(id, display_name, handle)
  values (tests.get_supabase_uid('bob@test.dev'), 'Bob', 'bob_c');
select is(
  (select count(*)::int from public.profile_private where id = tests.get_supabase_uid('alice@test.dev')),
  0, 'another user cannot read your private phone row (self-RLS)');

-- ── SEC-1: name embeds still work (profiles stays fully readable) ─────────────
select is(
  (select display_name from public.profiles where id = tests.get_supabase_uid('alice@test.dev')),
  'Alice', 'display_name still readable by another user (embeds unbroken)');

-- ── PROF-1: handle is unique case-insensitively ─────────────────────────────
select throws_ok(
  $$ update public.profiles set handle = 'Alice_C' where id = tests.get_supabase_uid('bob@test.dev') $$,
  '23505', null,
  'duplicate handle (case-insensitive) is rejected');

select * from finish();
rollback;
