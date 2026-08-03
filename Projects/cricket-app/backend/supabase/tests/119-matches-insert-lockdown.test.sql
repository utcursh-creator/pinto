begin;
select plan(7);
-- CRITICAL (whole-system review #2, 2026-07-28): create_match's SEC-5 team-admin
-- gate is bypassable, because the TABLE still grants INSERT with a policy that
-- only checks `owner_id = auth.uid()`. team_a_id, team_b_id and scorer_id are
-- unchecked.
--
-- One PostgREST call makes an attacker the scorer of a match between two clubs
-- she has nothing to do with. Every downstream guard then passes, because each
-- one only asks "are you the scorer?": add_squad_member accepts the victims'
-- real players (the team IS in the match, the player IS in that team),
-- start_innings flips it live and notifies every squad member, record_ball and
-- set_match_result complete it. The fake game then counts in both victims'
-- public team_career_stats and folds into real players' career records - a
-- golden duck, a 0/40 spell - all readable with no login. Neither victim can
-- remove it: delete_match and matches_delete_owner both require
-- owner_id = auth.uid(), and transfer_scorer refuses once status is 'complete'.
--
-- This is the exact shape 20260707130100_revoke_direct_writes.sql was written to
-- close ("the RPC holds the rule, but the TABLE is still granted"). That
-- migration revoked UPDATE on matches and deliberately left INSERT.

select tests.create_supabase_user('victim@x.dev');
select tests.create_supabase_user('mallory@x.dev');

select tests.authenticate_as('victim@x.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('victim@x.dev'), 'Victim');
select public.create_team('Victim FC', 'Pune') as _v1 \gset
select public.create_team('Rivals CC', 'Pune') as _v2 \gset
select public.add_guest_member(:'_v1'::uuid, 'RealPlayer') as _rp \gset

select tests.authenticate_as('mallory@x.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('mallory@x.dev'), 'Mallory');

-- 1-2. she is nobody on either team, and the RPC correctly refuses her
select ok(not public.is_team_admin(:'_v1'::uuid) and not public.is_team_admin(:'_v2'::uuid),
  'the attacker is not an admin of either club');
select throws_ok(
  format($$ select public.create_match(%L, %L, 5) $$, :'_v1', :'_v2'),
  'P0001', null, 'create_match still enforces the SEC-5 team-admin gate');

-- 3. THE HOLE: the same thing via a raw insert, which the RPC gate never sees
select throws_ok(
  format($$ insert into public.matches(team_a_id, team_b_id, owner_id, scorer_id, overs_limit)
            values (%L, %L, %L, %L, 5) $$,
         :'_v1', :'_v2',
         tests.get_supabase_uid('mallory@x.dev'), tests.get_supabase_uid('mallory@x.dev')),
  '42501', null,
  'a raw INSERT of a match between two clubs she has no part in is refused');

-- 4. and she cannot install herself as scorer on someone else's legitimate match
select tests.authenticate_as('victim@x.dev');
select public.create_match(:'_v1'::uuid, :'_v2'::uuid, 5) as _real \gset
select tests.authenticate_as('mallory@x.dev');
select throws_ok(
  format($$ insert into public.matches(team_a_id, team_b_id, owner_id, scorer_id, overs_limit)
            values (%L, %L, %L, %L, 5) $$,
         :'_v1', :'_v2',
         tests.get_supabase_uid('mallory@x.dev'), tests.get_supabase_uid('victim@x.dev')),
  '42501', null, 'nor can she fabricate one naming the victim as scorer');

-- 5. the legitimate path is untouched: an admin of ONE participating team
select tests.authenticate_as('victim@x.dev');
select lives_ok(
  format($$ select public.create_match(%L, %L, 20) $$, :'_v1', :'_v2'),
  'a real team admin can still create a match through the RPC');

-- 6. and their own raw insert is still allowed, because they ARE an admin -
-- the rule is participation, not "only the RPC may write".
select lives_ok(
  format($$ insert into public.matches(team_a_id, team_b_id, owner_id, scorer_id, overs_limit)
            values (%L, %L, %L, %L, 20) $$,
         :'_v1', :'_v2',
         tests.get_supabase_uid('victim@x.dev'), tests.get_supabase_uid('victim@x.dev')),
  'a participating admin may still insert directly');

-- 7. the attacker never became a scorer anywhere
select is(
  (select count(*)::int from public.matches
    where scorer_id = tests.get_supabase_uid('mallory@x.dev')),
  0, 'the attacker scores nothing');

select * from finish();
rollback;
