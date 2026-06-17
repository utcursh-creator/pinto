begin;
select plan(5);

select tests.create_supabase_user('p@m.dev');
select tests.authenticate_as('p@m.dev');
insert into public.profiles(id, display_name, phone, city, batting_style, playing_role)
  values (tests.get_supabase_uid('p@m.dev'), 'Pat', '+910000000000', 'Pune', 'right', 'batter');
select tests.get_supabase_uid('p@m.dev') as _uid \gset

-- become anon and resolve the minimal public view
select tests.clear_authentication();
select is((select display_name from public.public_profile_minimal(:'_uid'::uuid)), 'Pat', 'anon resolves display_name');
select is((select batting_style::text from public.public_profile_minimal(:'_uid'::uuid)), 'right', 'anon resolves batting_style');
select is((select count(*)::int from public.public_profile_minimal('00000000-0000-0000-0000-000000000000'::uuid)), 0, 'unknown id returns no rows');
-- the function deliberately does not expose phone or city (parse-time 42703)
select throws_ok($$ select phone from public.public_profile_minimal('00000000-0000-0000-0000-000000000000'::uuid) $$, '42703', null, 'phone is not exposed');
select throws_ok($$ select city  from public.public_profile_minimal('00000000-0000-0000-0000-000000000000'::uuid) $$, '42703', null, 'city is not exposed');

select * from finish();
rollback;
