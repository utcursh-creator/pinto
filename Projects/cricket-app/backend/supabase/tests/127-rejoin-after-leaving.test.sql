begin;
select plan(8);
-- Whole-system review #2 (2026-07-28): a player who leaves a team can never
-- rejoin it through a join request.
--
-- leave_team is a soft delete - it stamps left_at so the player's match history
-- stays attached to the same membership row. respond_join_request then does
--
--   insert into team_members ... on conflict (team_id, profile_id) do nothing
--
-- and that row still exists, so the insert quietly does NOTHING while the
-- request is marked 'approved' anyway. The captain is told it worked. The
-- player is still off the roster.
--
-- And the request is now consumed, so raising a fresh one fails identically:
-- the lockout is PERMANENT. Leaving a club after an argument and coming back
-- next season is an utterly ordinary thing to do in club cricket.
--
-- accept_invite already gets this right (it revives the tombstone deliberately,
-- with a comment saying so), which is what makes this a gap rather than a
-- design choice.
--
-- NOTE the precondition, learned the hard way while writing this test:
-- leave_team HARD-deletes a member who never played and only tombstones one who
-- HAS match history. So this bug reaches exactly the people it hurts most - the
-- players who actually turned out for the club. Someone who joined and left
-- without playing rejoins fine, because their row was really gone. The squad
-- membership below is therefore load-bearing, not scenery: without it this test
-- passes against the broken function.

select tests.create_supabase_user('cap@rj.dev');
select tests.create_supabase_user('player@rj.dev');

select tests.authenticate_as('cap@rj.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@rj.dev'), 'Cap');
select public.create_team('Rejoin CC', 'Pune') as _t \gset
select public.create_team_invite(:'_t'::uuid) as _tok \gset

select tests.authenticate_as('player@rj.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('player@rj.dev'), 'Player');
select public.accept_invite(:'_tok'::text) as _mem \gset

-- Give them real match history, which is what makes leaving a TOMBSTONE rather
-- than a delete - and therefore what triggers the bug.
select tests.authenticate_as('cap@rj.dev');
select public.create_team('Rejoin Foes', 'Pune') as _o \gset
select public.add_guest_member(:'_o'::uuid, 'F1') as _f1 \gset
select public.create_match(:'_t'::uuid, :'_o'::uuid, 20) as _m \gset
select public.add_squad_member(:'_m'::uuid, :'_t'::uuid, :'_mem'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_o'::uuid, :'_f1'::uuid);
select tests.authenticate_as('player@rj.dev');

-- 1. they are on the roster
select is(
  (select count(*)::int from public.team_members
    where id = :'_mem'::uuid and left_at is null),
  1, 'the player joined');

-- they fall out with the captain and leave
select public.leave_team(:'_mem'::uuid);
select is(
  (select count(*)::int from public.team_members
    where id = :'_mem'::uuid and left_at is null),
  0, 'and then left');

-- next season, they ask to come back
select public.request_to_join(:'_t'::uuid) as _req \gset

select tests.authenticate_as('cap@rj.dev');
select public.respond_join_request(:'_req'::uuid, true);

-- 3. THE BUG: the captain approved, so the player must actually be back
select is(
  (select count(*)::int from public.team_members
    where id = :'_mem'::uuid and left_at is null),
  1, 'approving the request puts the returning player back on the roster');

-- 4. the SAME row, so their whole match history is still theirs
select is(
  (select count(*)::int from public.team_members
    where team_id = :'_t'::uuid
      and profile_id = tests.get_supabase_uid('player@rj.dev')),
  1, 'and it is the same membership row - no duplicate, history intact');

-- 5. the request reads as handled
select is(
  (select status::text from public.team_join_requests where id = :'_req'::uuid),
  'approved', 'the request is marked approved');

-- 6. CONTROL: rejecting must NOT put them back. If the fix simply revived the
--    tombstone whenever a request was answered, a captain DECLINING somebody
--    would readmit the very person they just turned away. Uses its own player
--    so it does not depend on assertion 3 having passed.
select tests.create_supabase_user('spurned@rj.dev');
select tests.authenticate_as('cap@rj.dev');
select public.create_team_invite(:'_t'::uuid) as _tok2 \gset
select tests.authenticate_as('spurned@rj.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('spurned@rj.dev'), 'Spurned');
select public.accept_invite(:'_tok2'::text) as _mem2 \gset
select tests.authenticate_as('cap@rj.dev');
select public.add_squad_member(:'_m'::uuid, :'_t'::uuid, :'_mem2'::uuid);
select tests.authenticate_as('spurned@rj.dev');
select public.leave_team(:'_mem2'::uuid);
select public.request_to_join(:'_t'::uuid) as _req2 \gset
select tests.authenticate_as('cap@rj.dev');
select public.respond_join_request(:'_req2'::uuid, false);
select is(
  (select count(*)::int from public.team_members
    where id = :'_mem2'::uuid and left_at is null),
  0, 'a REJECTED request leaves a former member off the roster');

-- 7. CONTROL: an ordinary first-time joiner still works
select tests.create_supabase_user('newbie@rj.dev');
select tests.authenticate_as('newbie@rj.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('newbie@rj.dev'), 'Newbie');
select public.request_to_join(:'_t'::uuid) as _req3 \gset
select tests.authenticate_as('cap@rj.dev');
select public.respond_join_request(:'_req3'::uuid, true);
select is(
  (select count(*)::int from public.team_members
    where team_id = :'_t'::uuid
      and profile_id = tests.get_supabase_uid('newbie@rj.dev')
      and left_at is null),
  1, 'somebody who never played for the club still joins normally');

-- 8. CONTROL: the DO UPDATE is confined to tombstones. A pending request from
--    somebody who is ALREADY an active member must not rewrite their row - an
--    unguarded `do update set role = 'player'` would silently demote a captain
--    to player the moment anyone approved a stray request. Seeded directly,
--    because the app has no legitimate route to this state - which is exactly
--    why it needs pinning rather than assuming.
set local role postgres;
insert into public.team_join_requests(team_id, requester_id, status)
values (:'_t'::uuid, tests.get_supabase_uid('cap@rj.dev'), 'pending')
returning id as _req4 \gset
select tests.authenticate_as('cap@rj.dev');
select public.respond_join_request(:'_req4'::uuid, true);
select is(
  (select role::text from public.team_members
    where team_id = :'_t'::uuid and profile_id = tests.get_supabase_uid('cap@rj.dev')),
  'captain', 'approving a stray request does not demote a sitting captain');

select * from finish();
rollback;
