begin;
select plan(10);
-- HIGH batch (penetration review 2026-07-07). Every case below is an attack an
-- ordinary authenticated user could run today with one PostgREST call. The
-- pattern in all of them: an RPC holds the rule, but the TABLE is still granted
-- directly, so the client can step around the RPC entirely.

select tests.create_supabase_user('own@h.dev');
select tests.create_supabase_user('atk@h.dev');

-- victim: a team, a match, a squad
select tests.authenticate_as('own@h.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('own@h.dev'), 'Owner');
select public.create_team('Owner XI', 'P') as _ot \gset
select public.create_team('Owner B', 'P') as _ob \gset
select public.add_guest_member(:'_ot'::uuid, 'o1') as _o1 \gset
select public.add_guest_member(:'_ob'::uuid, 'ob1') as _ob1 \gset
select public.create_match(:'_ot'::uuid, :'_ob'::uuid, 10) as _om \gset

-- attacker: their own team + tournament
select tests.authenticate_as('atk@h.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('atk@h.dev'), 'Atk');
select public.create_team('Atk XI', 'P') as _at \gset
select public.create_tournament('Fake Cup', 4, 2, 8) as _tt \gset

-- 1. tournament_teams: the consent model must not be bypassable by a raw INSERT
select throws_ok(
  format($$ insert into public.tournament_teams(tournament_id, team_id, group_label)
            values (%L, %L, 'A') $$, :'_tt', :'_ot'),
  '42501', NULL,
  'a raw INSERT cannot enrol someone else''s team in my tournament');

-- 2. tournament_matches: attaching a stranger's match to my tournament is IDOR
--    (it also permanently blocks them from deleting their own match)
select throws_ok(
  format($$ insert into public.tournament_matches(match_id, tournament_id, stage)
            values (%L, %L, 'group') $$, :'_om', :'_tt'),
  '42501', NULL,
  'a raw INSERT cannot attach a stranger''s match to my tournament');

-- 3. matches: a blanket UPDATE grant makes every set_match_result guard
--    decorative (forge a result, swap a team in, rewrite the winner)
select throws_ok(
  format($$ update public.matches set result = '{"result_type":"win_by_runs"}'::jsonb,
              status = 'complete' where id = %L $$, :'_om'),
  '42501', NULL,
  'a non-scorer cannot PATCH a match row directly');

-- and even the OWNER must not bypass set_match_result's validation
select tests.authenticate_as('own@h.dev');
select throws_ok(
  format($$ update public.matches set status = 'complete' where id = %L $$, :'_om'),
  '42501', NULL,
  'even the scorer cannot PATCH status/result directly - the RPC owns that');

-- the legitimate toss write still works, through its own RPC
select lives_ok(
  format($$ select public.set_toss(%L, %L, 'bat') $$, :'_om', :'_ot'),
  'the scorer sets the toss via set_toss');
select is((select toss_decision::text from public.matches where id = :'_om'::uuid), 'bat',
  'the toss landed');

-- 4. add_squad_member must not accept a team that is not in this match, nor a
--    member that is not in that team - it forges PUBLIC career stats otherwise
select throws_ok(
  format($$ select public.add_squad_member(%L, %L, %L) $$, :'_om', :'_at', :'_o1'),
  'P0001', 'that team is not in this match',
  'a squad cannot name a team outside the match');
select throws_ok(
  format($$ select public.add_squad_member(%L, %L, %L) $$, :'_om', :'_ot', :'_ob1'),
  'P0001', 'that player is not in that team',
  'a squad cannot name a player from another team');

-- re-adding the same player must be idempotent, not a duplicate-key dead end
-- (this is what stranded resumed match setup)
select public.add_squad_member(:'_om'::uuid, :'_ot'::uuid, :'_o1'::uuid, 1, false, false);
select lives_ok(
  format($$ select public.add_squad_member(%L, %L, %L, 2, true, false) $$,
    :'_om', :'_ot', :'_o1'),
  're-adding a squad member updates instead of erroring');
select is((select batting_order from public.match_squad
            where match_id = :'_om'::uuid and team_member_id = :'_o1'::uuid), 2,
  'the re-add applied the new batting order');

select * from finish();
rollback;
