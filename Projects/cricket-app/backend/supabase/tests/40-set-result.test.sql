begin;
select plan(3);
select tests.create_supabase_user('cap@s.dev');
select tests.create_supabase_user('out@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset

-- scorer sets a no-result; the match completes with no play-derived margin
select public.set_match_result(:'_mt'::uuid, 'no_result');
select is((select status::text from public.matches where id = :'_mt'::uuid), 'complete', 'no_result completes the match');
select is((select result->>'result_type' from public.matches where id = :'_mt'::uuid), 'no_result', 'result_type recorded');

-- a non-scorer cannot set a result
select tests.authenticate_as('out@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('out@s.dev'),'Out');
select throws_ok(
  $$ select public.set_match_result((select id from public.matches limit 1), 'abandoned') $$,
  'P0001', 'not authorized', 'non-scorer cannot set a match result');
select * from finish();
rollback;
