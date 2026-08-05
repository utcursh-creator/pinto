begin;
select plan(9);
-- CRITICAL regression test (penetration review 2026-07-07): the team_members
-- UPDATE self-branch let ANY authenticated user become admin of ANY team with a
-- single PATCH. This test reproduces the exact attack and asserts it now fails,
-- while every legitimate path still works.

select tests.create_supabase_user('victim@t.dev');
select tests.create_supabase_user('attacker@t.dev');

-- victim owns a team (create_team makes them captain)
select tests.authenticate_as('victim@t.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('victim@t.dev'), 'Victim');
select public.create_team('Victim XI', 'Pune') as _vt \gset

-- attacker owns their own throwaway team, so they hold a membership row to pivot from
select tests.authenticate_as('attacker@t.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('attacker@t.dev'), 'Attacker');
select public.create_team('Attacker XI', 'Pune') as _at \gset
select id as _amem from public.team_members
  where team_id = :'_at'::uuid and profile_id = tests.get_supabase_uid('attacker@t.dev') \gset

select is(public.is_team_admin(:'_vt'::uuid), false,
  'precondition: the attacker is not an admin of the victim team');

-- THE ATTACK: re-point my own membership row at the victim team, as admin.
--
-- This used to be stopped by a TRIGGER ('a membership cannot be moved to another
-- team'), which meant the client could still reach the table and everything
-- depended on that one guard being right. Review #3: the UPDATE grant also made
-- the last-captain guard in set_team_member_role optional. The grant is gone, so
-- the attack now dies a layer earlier - at permission, before any trigger runs.
-- The trigger stays where it is, as defence in depth for anything server-side.
select throws_ok(
  format($$ update public.team_members set team_id = %L, role = 'admin' where id = %L $$,
    :'_vt', :'_amem'),
  '42501', null,
  'the takeover PATCH is now rejected - at permission, not at the trigger');

select is(public.is_team_admin(:'_vt'::uuid), false,
  'the attacker is still not an admin of the victim team');

-- the weaker form: self-promote inside a team I am not in. This used to be a
-- lives_ok - "RLS filters it to no rows rather than erroring" - which was true
-- and was also the tell: the client could still REACH the table, so the whole
-- defence was one policy predicate being right. Review #3 took the grant away,
-- so the same attempt is now refused outright.
select tests.authenticate_as('victim@t.dev');
select public.add_guest_member(:'_vt'::uuid, 'Guesty') as _g \gset
select tests.authenticate_as('attacker@t.dev');
select throws_ok(
  format($$ update public.team_members set role = 'admin' where id = %L $$, :'_g'),
  '42501', null,
  'a non-admin UPDATE is refused at permission - it no longer depends on the '
  'policy filtering the row out');
select is((select role::text from public.team_members where id = :'_g'::uuid), 'player',
  'the victim team''s guest was NOT promoted by the attacker');

-- legitimate admin path still works, through the RPC
select tests.authenticate_as('victim@t.dev');
select lives_ok(
  format($$ select public.set_team_member_role(%L, 'admin') $$, :'_g'),
  'a team admin can set a member''s role via the RPC');
select is((select role::text from public.team_members where id = :'_g'::uuid), 'admin',
  'the role change applied');

-- the RPC is authorization-gated too
select tests.authenticate_as('attacker@t.dev');
select throws_ok(
  format($$ select public.set_team_member_role(%L, 'player') $$, :'_g'),
  'P0001', 'not authorized',
  'a non-admin cannot use the role RPC');

-- last-captain guard is now server-side (TEAM-5 was UI-only)
select tests.authenticate_as('victim@t.dev');
select id as _cap from public.team_members
  where team_id = :'_vt'::uuid and role = 'captain' \gset
select throws_ok(
  format($$ select public.set_team_member_role(%L, 'player') $$, :'_cap'),
  'P0001', 'a team needs at least one captain',
  'the only captain cannot be demoted');

select * from finish();
rollback;
