begin;
select plan(6);
-- CRITICAL (whole-system review #2, 2026-07-28): deleting your account hands
-- your identity to whoever asks for it.
--
-- delete_my_account detaches each membership by setting profile_id = null and
-- guest_name = 'Deleted user', so match history keeps naming a row rather than a
-- person - which is the right instinct. But a row with profile_id null and a
-- guest_name IS EXACTLY WHAT request_guest_claim CALLS A CLAIMABLE GUEST. So any
-- stranger can claim the departed person's membership, and once a captain
-- approves it, that stranger owns their innings, wickets and career record on
-- that team forever.
--
-- The person asked to be forgotten. The one thing that must not happen is
-- someone else inheriting them.

select tests.create_supabase_user('leaver@d.dev');
select tests.create_supabase_user('cap@d.dev');
select tests.create_supabase_user('vulture@d.dev');

select tests.authenticate_as('cap@d.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@d.dev'), 'Cap');
select public.create_team('Ghost XI', 'Pune') as _t \gset
select public.create_team_invite(:'_t'::uuid) as _tok \gset
select public.add_guest_member(:'_t'::uuid, 'Ordinary Guest') as _guest \gset

select tests.authenticate_as('leaver@d.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('leaver@d.dev'), 'Leaver');
select public.accept_invite(:'_tok'::text) as _lm \gset

-- they play, so the membership must survive deletion for the scorecard's sake
select tests.authenticate_as('cap@d.dev');
select public.create_team('Ghost Foes', 'Pune') as _o \gset
select public.add_guest_member(:'_o'::uuid, 'GF1') as _gf1 \gset
select public.add_guest_member(:'_o'::uuid, 'GF2') as _gf2 \gset
select public.create_match(:'_t'::uuid, :'_o'::uuid, 5) as _m \gset
select public.add_squad_member(:'_m'::uuid, :'_t'::uuid, :'_lm'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_t'::uuid, :'_guest'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_o'::uuid, :'_gf1'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_o'::uuid, :'_gf2'::uuid);

select tests.authenticate_as('leaver@d.dev');
select public.delete_my_account();

-- 1-2. the row survives and no longer names a person
select is(
  (select count(*)::int from public.team_members where id = :'_lm'::uuid),
  1, 'the membership survives so the scorecard can still render the match');
select is(
  (select profile_id from public.team_members where id = :'_lm'::uuid),
  null, 'and it no longer points at the deleted person');

-- 3. THE BUG: a stranger must not be able to claim it
select tests.authenticate_as('vulture@d.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('vulture@d.dev'), 'Vulture');
select throws_ok(
  format($$ select public.request_guest_claim(%L) $$, :'_lm'),
  'P0001', null,
  'a deleted account''s membership cannot be claimed by anyone else');

-- 4. an ORDINARY guest is still claimable - the fix must not break the feature
select lives_ok(
  format($$ select public.request_guest_claim(%L) $$, :'_guest'),
  'an ordinary guest can still be claimed');

-- 5. the match still names the departed row, so history is intact
select is(
  (select count(*)::int from public.match_squad
    where match_id = :'_m'::uuid and team_member_id = :'_lm'::uuid),
  1, 'the match they played still names the membership');

-- 6. and they are off the roster - deleting the account is also leaving
select is(
  (select count(*)::int from public.team_members
    where id = :'_lm'::uuid and left_at is null),
  0, 'a deleted account is no longer on the active roster');

select * from finish();
rollback;
