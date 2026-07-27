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

-- UPDATE on matches is no longer granted to clients at all (penetration review
-- 2026-07-07): a blanket grant made every guard in set_match_result and
-- update_match_schedule decorative. What used to be an RLS-filtered silent
-- no-op is now a hard permission denial - a strictly stronger guarantee.
select throws_ok($$ update public.matches set venue = 'X' where overs_limit = 20 $$,
  '42501', NULL, 'direct UPDATE on matches is denied - the RPCs own mutation');

select * from finish();
rollback;
