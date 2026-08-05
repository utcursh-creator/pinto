begin;
select plan(12);
-- MEDIUM (penetration review 2026-07-07, team-member-delete-fk-restrict):
-- "Leave this team" and "Remove this player" are a raw
-- `delete from team_members where id = ...`. Nine foreign keys point at that
-- table with NO ACTION - match_squad, both innings openers, and six delivery
-- columns - so the moment a player has appeared in ONE match the delete raises
-- 23503 and the button shows a raw Postgres error forever. The people most
-- likely to leave a team are exactly the ones who have played for it.
--
-- Deleting is also the wrong thing: their history is real and the scorecard
-- must keep naming them. So departure becomes a state, not an erasure - and
-- the row is only truly deleted when there is no history to protect.

select tests.create_supabase_user('cap@l.dev');
select tests.create_supabase_user('plr@l.dev');

select tests.authenticate_as('cap@l.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@l.dev'), 'Cap');
select public.create_team('Leavers XI', 'Pune') as _t \gset
select public.create_team('Rivals XI', 'Pune') as _o \gset
select public.add_guest_member(:'_t'::uuid, 'Never Played') as _fresh \gset
select public.add_guest_member(:'_t'::uuid, 'Has History') as _veteran \gset
select public.add_guest_member(:'_o'::uuid, 'Opp1') as _opp1 \gset
select public.add_guest_member(:'_o'::uuid, 'Opp2') as _opp2 \gset

-- give the veteran a match: squad + an actual delivery
select public.create_match(:'_t'::uuid, :'_o'::uuid, 5) as _m \gset
select public.add_squad_member(:'_m'::uuid, :'_t'::uuid, :'_veteran'::uuid);
-- NOTE: _fresh is deliberately NOT put in the squad - that is the point.
select public.add_squad_member(:'_m'::uuid, :'_o'::uuid, :'_opp1'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_o'::uuid, :'_opp2'::uuid);

-- 1. THE BUG: the raw delete cannot work for someone who has played.
--    Clients can no longer DELETE from team_members at all (review #3 - the
--    grant made leave_team's tombstone optional), so the FK is proved as the
--    OWNER. The point of this assertion is the referential reason the RPC
--    exists, not who is allowed to try.
select current_role as _roleback \gset
set local role postgres;
select throws_ok(
  format($$ delete from public.team_members where id = %L $$, :'_veteran'),
  '23503', null,
  'even as the owner the raw delete fails on the FKs - this is why leave_team '
  'tombstones instead of deleting');
set local role :_roleback;

-- 2-4. leave_team on a player with history keeps the row and stamps the exit
select lives_ok(
  format($$ select public.leave_team(%L) $$, :'_veteran'),
  'leave_team succeeds for a player who has played');
select is(
  (select count(*)::int from public.team_members where id = :'_veteran'::uuid),
  1, 'the row survives, so the scorecard can still name them');
select isnt(
  (select left_at from public.team_members where id = :'_veteran'::uuid),
  null, 'their departure is recorded');

-- 5-6. a member with no history is removed outright - no tombstones for nothing
select lives_ok(
  format($$ select public.leave_team(%L) $$, :'_fresh'),
  'leave_team succeeds for a player with no history');
select is(
  (select count(*)::int from public.team_members where id = :'_fresh'::uuid),
  0, 'a member who never played is deleted outright');

-- 7. a departed member is no longer part of the CURRENT roster
select is(
  (select count(*)::int from public.team_members
    where team_id = :'_t'::uuid and left_at is null
      and id = :'_veteran'::uuid),
  0, 'a departed player is off the current roster');

-- 8. ...but the team still has its captain on it
select is(
  (select count(*)::int from public.team_members
    where team_id = :'_t'::uuid and left_at is null),
  1, 'the current roster is just the captain now');

-- 9. the last captain cannot leave and orphan the team
select throws_ok(
  format($$ select public.leave_team(%L) $$,
    (select id from public.team_members
      where team_id = :'_t'::uuid and profile_id = tests.get_supabase_uid('cap@l.dev'))),
  'P0001', null, 'the last captain cannot walk out of their own team');

-- 10. a stranger cannot remove someone from a team they have nothing to do with
select tests.authenticate_as('plr@l.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('plr@l.dev'), 'Plr');
select throws_ok(
  format($$ select public.leave_team(%L) $$, :'_opp1'),
  'P0001', null, 'a stranger cannot remove another team''s player');

-- 11-12. departing must also END the access that membership granted, or
-- "leaving" is cosmetic: the row is still there and the authz helpers read it.
select tests.authenticate_as('plr@l.dev');
select public.create_team('Plr XI', 'Pune') as _pt \gset
select ok(public.is_team_member(:'_pt'::uuid), 'a present member is a member');
reset role;
update public.team_members set left_at = now()
  where team_id = :'_pt'::uuid and profile_id = tests.get_supabase_uid('plr@l.dev');
select tests.authenticate_as('plr@l.dev');
select ok(not public.is_team_member(:'_pt'::uuid),
  'someone who has left is no longer a member for authz purposes');

select * from finish();
rollback;
