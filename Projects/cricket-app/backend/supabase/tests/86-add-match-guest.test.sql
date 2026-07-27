begin;
select plan(4);
-- SCOR-11: the match scorer can add a guest to EITHER side; a non-scorer cannot;
-- the team must be in the match.
select tests.create_supabase_user('scorer@s.dev');
select tests.create_supabase_user('rando@s.dev');

select tests.authenticate_as('scorer@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('scorer@s.dev'), 'Scorer');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
-- team C is deliberately NOT in the match
select public.create_team('C', 'P') as _c \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset

-- scorer adds a guest to the OPPONENT team B (which they don't admin) -> ok
select isnt(public.add_match_guest(:'_m'::uuid, :'_b'::uuid, 'Guest B'), null,
  'the scorer can add a guest to a participating team they do not admin');
select is(
  (select count(*)::int from public.team_members where team_id = :'_b'::uuid and guest_name = 'Guest B'),
  1, 'the guest is now on team B');

-- adding to a team not in the match is rejected
select throws_ok(
  format($$ select public.add_match_guest(
       %L, %L, 'Nope') $$, :'_m', :'_c'),
  'P0001', 'team is not in this match', 'cannot add a guest to a non-participating team');

-- a non-scorer cannot add a guest
select tests.authenticate_as('rando@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('rando@s.dev'), 'Rando');
select throws_ok(
  format($$ select public.add_match_guest(
       %L, %L, 'Sneaky') $$, :'_m', :'_a'),
  'P0001', 'not authorized', 'a non-scorer cannot add a match guest');

select * from finish();
rollback;
