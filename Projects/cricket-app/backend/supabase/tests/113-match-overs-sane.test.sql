begin;
select plan(8);
-- Found while reading the match-setup path (fix run 2026-07-07): `overs_limit`
-- is `int not null` with NO check constraint, and create_match passes whatever
-- it is given straight through. A scorer who types 0 in the Overs box gets a
-- match whose innings is over before a ball is bowled (max_legal = 0, so the
-- fold closes the innings on delivery 1) - and there is no way back out of a
-- started match. Negative overs are worse: max_legal goes negative and every
-- comparison in the fold is nonsense. balls_per_over has the same hole.
--
-- The guard belongs on the server: the RPC gives a readable reason, and the
-- check constraint stops a direct PostgREST insert from bypassing the RPC.

select tests.create_supabase_user('ov@m.dev');
select tests.authenticate_as('ov@m.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('ov@m.dev'), 'Ov');
select public.create_team('Overs A', 'Pune') as _a \gset
select public.create_team('Overs B', 'Pune') as _b \gset

-- 1-3. the RPC refuses nonsense rather than creating an unplayable match
select throws_ok(
  format($$ select public.create_match(%L, %L, 0) $$, :'_a', :'_b'),
  'P0001', null, 'create_match refuses 0 overs');
select throws_ok(
  format($$ select public.create_match(%L, %L, -3) $$, :'_a', :'_b'),
  'P0001', null, 'create_match refuses negative overs');
select throws_ok(
  format($$ select public.create_match(%L, %L, 1000) $$, :'_a', :'_b'),
  'P0001', null, 'create_match refuses an absurd overs limit');

-- 4-5. balls per over has the same hole
select throws_ok(
  format($$ select public.create_match(%L, %L, 20, 0) $$, :'_a', :'_b'),
  'P0001', null, 'create_match refuses 0 balls per over');
select throws_ok(
  format($$ select public.create_match(%L, %L, 20, 50) $$, :'_a', :'_b'),
  'P0001', null, 'create_match refuses an absurd balls-per-over');

-- 6. the ordinary case still works
select lives_ok(
  format($$ select public.create_match(%L, %L, 20) $$, :'_a', :'_b'),
  'a normal 20-over match is still created');

-- 7. a 90-over red-ball innings is legitimate and must not be blocked
select lives_ok(
  format($$ select public.create_match(%L, %L, 90, 6) $$, :'_a', :'_b'),
  'a 90-over innings is allowed');

-- 8. the constraint also stops a direct insert that skips the RPC
select throws_ok(
  format($$ insert into public.matches(team_a_id, team_b_id, owner_id, scorer_id, overs_limit)
            values (%L, %L, %L, %L, 0) $$,
         :'_a', :'_b', tests.get_supabase_uid('ov@m.dev'), tests.get_supabase_uid('ov@m.dev')),
  '23514', null, 'a direct insert with 0 overs violates the check constraint');

select * from finish();
rollback;
