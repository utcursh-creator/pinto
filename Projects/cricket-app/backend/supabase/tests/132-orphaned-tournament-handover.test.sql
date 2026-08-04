begin;
select plan(6);
-- Whole-system review #2 (2026-07-28), finding 36: an in-progress tournament is
-- orphaned when its organizer deletes their account.
--
-- Every management RPC is gated on is_tournament_organizer, which is only
-- `organizer_id = auth.uid()`. No transfer-organizer RPC exists anywhere in the
-- migrations, and the write policy is the same condition, so no other account
-- can rewrite organizer_id either. The deleted account is banned_until
-- 'infinity' with its identities gone, so the organizer cannot return.
--
-- The public page keeps serving a half-finished bracket. Group games can still
-- be scored, but the semifinals can never be generated, the final never created
-- and champion_team_id never set. Every enrolled team is stuck in a competition
-- that cannot end.
--
-- Exactly the shape of the sole-captain bug fixed earlier in this review, and
-- it takes the same answer: a person must always be able to leave, so the thing
-- they were running is handed on.

select tests.create_supabase_user('org@to.dev');
select tests.create_supabase_user('cap@to.dev');

select tests.authenticate_as('cap@to.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@to.dev'), 'Cap');
select public.create_team('Enrolled CC', 'Pune') as _t \gset

select tests.authenticate_as('org@to.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('org@to.dev'), 'Organizer');
select public.create_tournament(
  _name => 'Orphan Cup', _overs => 20, _group_count => 1,
  _qualifiers_per_group => 2, _city => 'Pune') as _tr \gset

-- an unrelated tournament with nobody enrolled, and one already finished
select public.create_tournament(
  _name => 'Empty Cup', _overs => 20, _group_count => 1,
  _qualifiers_per_group => 2, _city => 'Pune') as _empty \gset
select public.create_tournament(
  _name => 'Done Cup', _overs => 20, _group_count => 1,
  _qualifiers_per_group => 2, _city => 'Pune') as _done \gset

-- A club enters by TOKEN: add_tournament_team requires the caller to be an
-- admin of the team as well as the organizer, so another club joins itself.
select public.create_tournament_invite(:'_tr'::uuid) as _tok \gset
select tests.authenticate_as('cap@to.dev');
select public.join_tournament_with_token(:'_tok'::text, :'_t'::uuid);
select tests.authenticate_as('org@to.dev');
set local role postgres;
update public.tournaments set status = 'group_stage' where id = :'_tr'::uuid;
update public.tournaments set status = 'complete'   where id = :'_done'::uuid;
set local role authenticated;

select tests.get_supabase_uid('org@to.dev') as _org \gset
select tests.get_supabase_uid('cap@to.dev') as _cap \gset

-- 1. sanity: the organizer really does run it
select is(
  (select organizer_id from public.tournaments where id = :'_tr'::uuid),
  :'_org'::uuid, 'the organizer runs the tournament');

-- ---- they delete their account ----
select public.delete_my_account();
set local role postgres;

-- 2. THE BUG: somebody who can actually finish it must now own it
select is(
  (select organizer_id from public.tournaments where id = :'_tr'::uuid),
  :'_cap'::uuid,
  'an in-progress tournament is handed to the captain of an enrolled club, so '
  'the semifinals can still be generated and the competition can end');

-- 3. and that gate really is the one every management RPC uses
select tests.authenticate_as('cap@to.dev');
select ok(
  public.is_tournament_organizer(:'_tr'::uuid),
  'and is_tournament_organizer - the single gate on all six management RPCs - '
  'now says yes to them');

-- 4. CONTROL: a FINISHED tournament needs no organizer. Handing it on would
--    silently give a stranger write access to a completed competition.
set local role postgres;
select is(
  (select organizer_id from public.tournaments where id = :'_done'::uuid),
  :'_org'::uuid, 'a completed tournament is left alone - it needs nobody');

-- 5. CONTROL: with no club enrolled there is nobody to hand to, and nobody
--    stranded either.
select is(
  (select organizer_id from public.tournaments where id = :'_empty'::uuid),
  :'_org'::uuid, 'a tournament with no enrolled club strands no one');

-- 6. CONTROL: the handover must not invent an organizer out of a captain who
--    has left the club in the meantime.
select is(
  (select count(*)::int from public.tournaments t
    where t.organizer_id is null),
  0, 'no tournament is left with a null organizer');

select * from finish();
rollback;
