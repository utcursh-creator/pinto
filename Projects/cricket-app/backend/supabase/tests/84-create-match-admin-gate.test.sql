begin;
select plan(2);
-- SEC-5: only an admin of a participating team may create a match.
select tests.create_supabase_user('cap@s.dev');
select tests.create_supabase_user('rando@s.dev');

-- cap owns both teams
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@s.dev'), 'Cap');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select isnt(public.create_match(:'_a'::uuid, :'_b'::uuid, 20), null,
  'a team admin can create a match involving their team');

-- a stranger who admins neither team cannot fabricate a match
select tests.authenticate_as('rando@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('rando@s.dev'), 'Rando');
select throws_ok(
  $$ select public.create_match(
       (select id from public.teams where name = 'A'),
       (select id from public.teams where name = 'B'), 20) $$,
  'P0001', 'must be an admin of one of the participating teams',
  'a non-member cannot fabricate a match between other teams');

select * from finish();
rollback;
