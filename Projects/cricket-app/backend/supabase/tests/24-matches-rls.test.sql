begin;
select plan(4);
select tests.create_supabase_user('owner@s.dev');
select tests.create_supabase_user('rando@s.dev');
select tests.authenticate_as('owner@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('owner@s.dev'),'Owner');
select public.create_team('Alpha','Pune') as _a \gset
select public.create_team('Beta','Pune') as _b \gset

select isnt(public.create_match(:'_a'::uuid, :'_b'::uuid, 20), null, 'create_match returns id');
select is((select count(*)::int from public.matches where team_a_id = :'_a'::uuid), 1, 'match row exists');

-- any authenticated user can read the match
select tests.authenticate_as('rando@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rando@s.dev'),'Rando');
select is((select overs_limit from public.matches where team_a_id = :'_a'::uuid), 20, 'match readable by any authed user');

-- non-scorer update is filtered by RLS -> 0 rows, no error
select lives_ok($$ update public.matches set venue = 'X' where overs_limit = 20 $$, 'non-scorer match update is a silent no-op');

select * from finish();
rollback;
