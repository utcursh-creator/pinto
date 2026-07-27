begin;
select plan(9);
-- Found while reading the match-setup path (fix run 2026-07-07): the Opponent
-- picker was fed by `from('teams').select('id,name,city').order('name')` with NO
-- limit and NO filter - every team in the database, pulled down on every visit
-- to Start-a-match and poured into a DropdownButton. At any real size that is
-- both a download the phone should never make and a list nobody can scroll to
-- find a club in.
--
-- What a scorer actually does is play the same handful of clubs again and again,
-- and type a name when it is someone new. So: a bounded RPC that defaults to
-- THIS user's recent opponents and searches by name otherwise.

select tests.create_supabase_user('opp@s.dev');
select tests.create_supabase_user('other@s.dev');

select tests.authenticate_as('opp@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('opp@s.dev'), 'Opp');
select public.create_team('Mine XI', 'Pune') as _mine \gset
select public.create_team('Rivals CC', 'Pune') as _riv \gset
select public.create_team('Zebra Club', 'Pune') as _zeb \gset
-- a team this user has nothing to do with
select tests.authenticate_as('other@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('other@s.dev'), 'Other');
select public.create_team('Strangers XI', 'Delhi') as _str \gset

-- our user has played Rivals CC before
select tests.authenticate_as('opp@s.dev');
select public.create_match(:'_mine'::uuid, :'_riv'::uuid, 20) as _m \gset

-- 1-2. with no query, the default list is who you actually play
select is(
  (select count(*)::int from public.search_opponent_teams(null)
    where id = :'_riv'::uuid),
  1, 'a recent opponent is offered with no query typed');
select is(
  (select count(*)::int from public.search_opponent_teams(null)
    where id = :'_str'::uuid),
  0, 'an unrelated team is NOT dumped into the default list');

-- 3-4. typing finds anyone, including a club you have never played
select is(
  (select count(*)::int from public.search_opponent_teams('Strangers')
    where id = :'_str'::uuid),
  1, 'a search by name finds a club you have never played');
select is(
  (select count(*)::int from public.search_opponent_teams('zeb')
    where id = :'_zeb'::uuid),
  1, 'the search is case-insensitive and matches a fragment');

-- 5. your own side is never offered as its own opponent
select is(
  (select count(*)::int from public.search_opponent_teams('Mine', :'_mine'::uuid)
    where id = :'_mine'::uuid),
  0, 'the team you already picked is excluded');

-- 6. the result set is bounded no matter how many teams match
reset role;
insert into public.teams(name, city, created_by)
  select 'Bulk Club ' || g, 'Pune', tests.get_supabase_uid('opp@s.dev')
  from generate_series(1, 40) g;
select tests.authenticate_as('opp@s.dev');
select cmp_ok(
  (select count(*)::int from public.search_opponent_teams('Bulk Club')),
  '<=', 25, 'the search result set is bounded');

-- 7. the default list is bounded too. This needs MORE THAN THE CAP of actual
-- past opponents - with the single opponent the fixture had, the assertion
-- passed with no limit at all (re-review 2026-07-07). Play 30 of the bulk clubs.
reset role;
insert into public.matches(team_a_id, team_b_id, owner_id, scorer_id, overs_limit)
  select :'_mine'::uuid, t.id, tests.get_supabase_uid('opp@s.dev'),
         tests.get_supabase_uid('opp@s.dev'), 20
    from public.teams t
   where t.name like 'Bulk Club %'
   limit 30;
select tests.authenticate_as('opp@s.dev');
select cmp_ok(
  (select count(*)::int from public.search_opponent_teams(null)),
  '>', 20, 'the fixture really does have more past opponents than a short list');
select cmp_ok(
  (select count(*)::int from public.search_opponent_teams(null)),
  '<=', 25, 'the default list is bounded');

-- 8. anonymous callers cannot enumerate teams through it
select tests.clear_authentication();
select throws_ok(
  $$ select * from public.search_opponent_teams('Bulk') $$,
  '42501', null, 'an anonymous caller cannot call it');

select * from finish();
rollback;
