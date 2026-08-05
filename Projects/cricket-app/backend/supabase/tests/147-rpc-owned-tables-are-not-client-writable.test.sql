begin;
select plan(15);
-- Review #3, the theme rather than the findings: FOUR of its worst items are one
-- mistake in four places - a table-level grant that makes an RPC's guards
-- decorative, or a grant lost when a function was dropped and recreated.
--
--   matches INSERT             -> a pre-'complete' match with an invented result
--   team_members I/U/D         -> every guard in leave_team, set_team_member_role
--                                 and the claim flow becomes optional
--   looking_for_posts UPDATE   -> expires_at, status and geog are client-settable,
--                                 so renew_post/cancel_post/_snap_geog are optional
--   discover_posts EXECUTE     -> dropped by the LIMIT migration, so proacl went
--                                 null and anon could call the geo feed
--
-- Review #2 fixed exactly this shape for `deliveries` and `match_squad`. It came
-- back because nothing was watching. The last assertion in this file is the
-- thing that watches: a DRIFT GUARD over the whole schema, so the next migration
-- that re-grants a write on an RPC-owned table fails the suite instead of
-- quietly reopening the hole.
--
-- Safe to revoke: the Flutter app writes NONE of these three tables directly -
-- every path already goes through an RPC (grepped, not assumed).

select tests.create_supabase_user('own@g.dev');
select tests.create_supabase_user('att@g.dev');
select tests.authenticate_as('own@g.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('own@g.dev'),'Owner');
select public.create_team('Grant A','Pune') as _a \gset
select public.create_team('Grant B','Pune') as _b \gset
-- TWO members on purpose: in the UNFIXED state the abuse attempts below SUCCEED,
-- so pointing them at the same row the controls use would delete it and make the
-- controls fail for a reason that has nothing to do with them.
select public.add_guest_member(:'_a'::uuid,'G0') as _g0 \gset
select public.add_guest_member(:'_a'::uuid,'G1') as _g1 \gset
select tests.authenticate_as('att@g.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('att@g.dev'),'Attacker');
select public.create_team('Attacker XI','Pune') as _x \gset

-- ============ matches ============
-- 1. Verified by hand first: an admin of ONE team could insert a match that was
--    already 'complete', with a result they made up, against any other team -
--    bypassing the scoring engine and set_match_result entirely. (Two STRANGER
--    teams was always refused by RLS; that half of the finding was overstated.)
select throws_ok(
  format($$ insert into public.matches(team_a_id,team_b_id,overs_limit,owner_id,scorer_id,status,result)
            values (%L,%L,20,%L,%L,'complete','{"type":"win","text":"we won"}'::jsonb) $$,
          :'_x', :'_a', tests.get_supabase_uid('att@g.dev'), tests.get_supabase_uid('att@g.dev')),
  '42501', null,
  'a client cannot INSERT a match at all - create_match owns who may play whom');

-- 2. CONTROL: the RPC still works, which is the whole point of revoking
select lives_ok(
  format($$ select public.create_match(%L,%L,20) $$, :'_x', :'_a'),
  'and create_match still creates one');

-- ============ team_members ============
select tests.authenticate_as('own@g.dev');
-- 3-5. the three writes that made the roster guards optional
select throws_ok(
  format($$ insert into public.team_members(team_id,profile_id,role)
            values (%L,%L,'player') $$, :'_a', tests.get_supabase_uid('att@g.dev')),
  '42501', null,
  'an admin cannot attach a real user to their roster by INSERT - consent '
  'belongs to the invite/claim flow, not to whoever runs the team');
select throws_ok(
  format($$ update public.team_members set role='player' where id=%L $$, :'_g0'),
  '42501', null,
  'nor demote by UPDATE, which is how the last-captain guard was bypassed');
select throws_ok(
  format($$ delete from public.team_members where id=%L $$, :'_g0'),
  '42501', null,
  'nor DELETE a member, which leave_team tombstones for a reason');

-- 6-8. CONTROLS: every legitimate roster path still works
select lives_ok(
  format($$ select public.add_guest_member(%L,'G2') $$, :'_a'),
  'add_guest_member still adds');
select lives_ok(
  format($$ select public.set_team_member_role(%L,'admin') $$, :'_g1'),
  'set_team_member_role still promotes');
select lives_ok(
  format($$ select public.leave_team(%L) $$, :'_g1'),
  'and leave_team still removes');

-- ============ looking_for_posts ============
select public.create_looking_for_post(
  'team_seeking_players'::public.lf_mode, 'practice_match'::public.lf_flair,
  18.52, 73.85, 'Need 2') as _p \gset

-- 9-10. the author's own post: the columns the RPCs exist to own
select throws_ok(
  format($$ update public.looking_for_posts set expires_at = now() + interval '10 years'
            where id = %L $$, :'_p'),
  '42501', null,
  'an author cannot hand their own ad an immortal expiry - renew_post decides '
  'how long a post lives, and refuses a played fixture a new lease without a '
  'new date');
select throws_ok(
  format($$ update public.looking_for_posts
              set geog = ST_SetSRID(ST_MakePoint(0,0),4326)::geography
            where id = %L $$, :'_p'),
  '42501', null,
  'nor move the ad anywhere on earth, which would defeat the ~550m coarsening '
  'that keeps a home address out of the feed');

-- 11-12. CONTROLS: the RPCs that own those columns still work
select lives_ok(format($$ select public.renew_post(%L) $$, :'_p'),
  'renew_post still renews');
select lives_ok(format($$ select public.cancel_post(%L) $$, :'_p'),
  'and cancel_post still cancels');

-- ============ discover_posts ============
-- 13. the LIMIT migration dropped and recreated the function without re-granting,
--     so proacl went null - which in Postgres means executable by PUBLIC.
-- Asserting "it has SOME acl" would pass if the function were revoked from
-- everyone, which breaks the feed - so name both halves of the contract.
select is(
  (select has_function_privilege('authenticated',
     'public.discover_posts(double precision,double precision,double precision,'
     'public.lf_mode,integer,timestamptz,public.skill_level,public.lf_flair,integer)',
     'EXECUTE')),
  true, 'a signed-in user can call the discover feed');
select is(
  (select has_function_privilege('anon',
     'public.discover_posts(double precision,double precision,double precision,'
     'public.lf_mode,integer,timestamptz,public.skill_level,public.lf_flair,integer)',
     'EXECUTE')),
  false, 'and an anonymous visitor cannot - the LIMIT migration recreated this '
         'function without re-granting, leaving proacl NULL, which in Postgres '
         'is not "no access" but access for everybody');

-- ============ THE DRIFT GUARD ============
-- 14. The reason this cluster came back at all. Any future migration that grants
--     a client write on a table an RPC owns fails HERE, with the table named.
select is(
  (select coalesce(string_agg(distinct table_name || '.' || privilege_type, ', '
                              order by table_name || '.' || privilege_type), '')
     from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee in ('authenticated','anon')
      and privilege_type in ('INSERT','UPDATE','DELETE')
      and table_name in ('matches','team_members','looking_for_posts',
                         'deliveries','match_squad','innings','tournaments',
                         'tournament_matches','guest_claim_requests')),
  '',
  'no client write grant on a table whose invariants live in an RPC. If this '
  'fails, a migration re-opened the hole: either route that write through the '
  'RPC, or move the invariant into a trigger and say so here');

select * from finish();
rollback;
