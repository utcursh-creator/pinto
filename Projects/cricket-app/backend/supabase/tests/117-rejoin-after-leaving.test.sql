begin;
select plan(12);
-- CONFIRMED HIGH x3 + MEDIUM x2 (fix-run re-review 2026-07-07): the `left_at`
-- tombstone introduced by 20260707180000_leave_team.sql made LEAVING A TEAM
-- IRREVERSIBLE. The row survives so old scorecards can still name the player -
-- which is right - but every re-entry path reads team_members without filtering
-- left_at, sees the tombstone, and treats the person as still present:
--
--   * accept_invite finds "an existing membership", returns it, and burns no
--     invite use - so the app cheerfully says "You joined the team" and nothing
--     happened.
--   * request_to_join raises 'you are already on this team' - on the very screen
--     that just offered them a Request to join button.
--   * add_guest_member refuses the name, so a guest who was removed can never be
--     re-added under the name everyone calls them.
--   * transfer_scorer counts a departed player as eligible, so live scoring can
--     be handed to someone who is no longer on the team.
--   * set_team_member_role's last-captain guard counts DEPARTED captains, so a
--     team can be demoted to zero captains and become unadministrable.
--
-- The fix is one idea: a departed membership is REVIVABLE. Re-entry clears
-- left_at on the existing row (preserving the history that hangs off its id)
-- rather than being blocked by it, and every "is this person on the team"
-- question filters left_at.

select tests.create_supabase_user('cap@r.dev');
select tests.create_supabase_user('plr@r.dev');
select tests.create_supabase_user('vice@r.dev');

select tests.authenticate_as('cap@r.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@r.dev'), 'Cap');
select public.create_team('Rejoin XI', 'Pune') as _t \gset

select tests.authenticate_as('plr@r.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('plr@r.dev'), 'Plr');
select tests.authenticate_as('vice@r.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('vice@r.dev'), 'Vice');

-- the player joins by invite, then leaves
select tests.authenticate_as('cap@r.dev');
select public.create_team_invite(:'_t'::uuid) as _tok1 \gset
select tests.authenticate_as('plr@r.dev');
select public.accept_invite(:'_tok1'::text) as _m1 \gset
select tests.authenticate_as('cap@r.dev');
select public.leave_team(:'_m1'::uuid);
-- (no match history, so that row is deleted outright - force the tombstone case
--  by giving them history first is covered below; here we test the CLEAN case)
select is((select count(*)::int from public.team_members
            where team_id = :'_t'::uuid and profile_id = tests.get_supabase_uid('plr@r.dev')),
          0, 'a member with no history is deleted outright, leaving no tombstone');

-- 2. a fresh invite works for them again
select public.create_team_invite(:'_t'::uuid) as _tok2 \gset
select tests.authenticate_as('plr@r.dev');
select isnt(public.accept_invite(:'_tok2'::text), null,
  'someone who left with no history can rejoin by invite');

-- ---- now the TOMBSTONE case: give them history, then leave ----
select tests.authenticate_as('cap@r.dev');
select public.create_team('Foes XI', 'Pune') as _o \gset
select public.add_guest_member(:'_o'::uuid, 'F1') as _f1 \gset
select public.add_guest_member(:'_o'::uuid, 'F2') as _f2 \gset
select public.add_guest_member(:'_t'::uuid, 'Benchy') as _bench \gset
select id as _plrm from public.team_members
  where team_id = :'_t'::uuid and profile_id = tests.get_supabase_uid('plr@r.dev') \gset
select public.create_match(:'_t'::uuid, :'_o'::uuid, 5) as _mt \gset
select public.add_squad_member(:'_mt'::uuid, :'_t'::uuid, :'_plrm'::uuid);
select public.add_squad_member(:'_mt'::uuid, :'_t'::uuid, :'_bench'::uuid);
select public.add_squad_member(:'_mt'::uuid, :'_o'::uuid, :'_f1'::uuid);
select public.add_squad_member(:'_mt'::uuid, :'_o'::uuid, :'_f2'::uuid);
select public.leave_team(:'_plrm'::uuid);
select isnt((select left_at from public.team_members where id = :'_plrm'::uuid), null,
  'a member WITH history keeps their row and is tombstoned');

-- 3. THE BUG: accept_invite must actually bring them back
select public.create_team_invite(:'_t'::uuid) as _tok3 \gset
select tests.authenticate_as('plr@r.dev');
select public.accept_invite(:'_tok3'::text) as _back \gset
select is((select left_at from public.team_members where id = :'_plrm'::uuid), null,
  'accepting an invite REVIVES the tombstoned membership');
select is(:'_back'::uuid, :'_plrm'::uuid,
  'and it revives the SAME row, so their match history still hangs off it');
select ok(public.is_team_member(:'_t'::uuid),
  'they are a member again for authz purposes');

-- 4. leave again, then come back the OTHER way - a join request
select tests.authenticate_as('cap@r.dev');
select public.leave_team(:'_plrm'::uuid);
select tests.authenticate_as('plr@r.dev');
select lives_ok(
  format($$ select public.request_to_join(%L) $$, :'_t'),
  'a departed player can ASK to rejoin (it used to say "you are already on this team")');

-- 5. a departed guest's name is not burned
select tests.authenticate_as('cap@r.dev');
select public.leave_team(:'_bench'::uuid);   -- Benchy has squad history -> tombstoned
select lives_ok(
  format($$ select public.add_guest_member(%L, 'Benchy') $$, :'_t'),
  'a removed guest''s name can be used again');

-- 6. a departed player is NOT an eligible scorer
select public.create_match(:'_t'::uuid, :'_o'::uuid, 5) as _m2 \gset
select throws_ok(
  format($$ select public.transfer_scorer(%L, %L) $$, :'_m2', tests.get_supabase_uid('plr@r.dev')),
  'P0001', null, 'scoring cannot be handed to someone who left the team');

-- 7. the last-captain guard must not count a DEPARTED captain
select public.create_team('Solo XI', 'Pune') as _s \gset
select public.create_team_invite(:'_s'::uuid) as _stok \gset
select tests.authenticate_as('vice@r.dev');
select public.accept_invite(:'_stok'::text) as _vm \gset
select tests.authenticate_as('cap@r.dev');
select public.set_team_member_role(:'_vm'::uuid, 'captain'::public.team_member_role);
-- two captains; the original leaves (no history -> hard delete)
select id as _capm from public.team_members
  where team_id = :'_s'::uuid and profile_id = tests.get_supabase_uid('cap@r.dev') \gset
select tests.authenticate_as('vice@r.dev');
select public.leave_team(:'_capm'::uuid);
select throws_ok(
  format($$ select public.set_team_member_role(%L, 'player') $$, :'_vm'),
  'P0001', null,
  'the remaining captain cannot demote themselves - a departed captain does not count');

-- 8. and a team that still has two PRESENT captains can demote one
select tests.authenticate_as('vice@r.dev');
select public.create_team('Duo XI', 'Pune') as _d \gset
select public.create_team_invite(:'_d'::uuid) as _dtok \gset
select tests.authenticate_as('plr@r.dev');
select public.accept_invite(:'_dtok'::text) as _dm \gset
select tests.authenticate_as('vice@r.dev');
select public.set_team_member_role(:'_dm'::uuid, 'captain'::public.team_member_role);
select lives_ok(
  format($$ select public.set_team_member_role(%L, 'player') $$, :'_dm'),
  'with two present captains one can still be demoted');

-- 9. the whole point of reviving the SAME row: the match they played before
-- leaving still names them, so the scorecard never loses a player.
select is(
  (select count(*)::int from public.match_squad
    where match_id = :'_mt'::uuid and team_member_id = :'_plrm'::uuid),
  1, 'the match they played before leaving still names them');

select * from finish();
rollback;
