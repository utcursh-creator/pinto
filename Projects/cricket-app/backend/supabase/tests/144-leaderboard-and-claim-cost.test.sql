begin;
select plan(7);
-- Whole-system review #2 (2026-07-28), findings 65 and 73.
--
-- Both are cost findings, and a cost fix is only worth having if it does not
-- change the answer - so most of this file is about the answer. The structural
-- half (a filtered CTE, an index, a hoisted auth.uid()) is asserted directly
-- against the catalog, because a timing assertion on a 3-row fixture would
-- prove nothing and would flake on CI.

select tests.create_supabase_user('org@lb.dev');
select tests.create_supabase_user('rando@lb.dev');
select tests.authenticate_as('rando@lb.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rando@lb.dev'),'Rando');
select tests.authenticate_as('org@lb.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('org@lb.dev'),'Org');

select public.create_team('LB A','Pune') as _a \gset
select public.create_team('LB B','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'Striker')   as _s  \gset
select public.add_guest_member(:'_a'::uuid,'NonStrike') as _ns \gset
select public.add_guest_member(:'_b'::uuid,'Bowler')    as _bw \gset
select public.add_guest_member(:'_b'::uuid,'Second')    as _b2 \gset

-- A DECOY: a membership that belongs to nobody in this tournament. Before the
-- fix the names CTE happily materialised rows like this one - every membership
-- in the database - to label at most fifty leaderboard rows.
select public.create_team('Nothing To Do With It','Pune') as _z \gset
select public.add_guest_member(:'_z'::uuid,'Decoy') as _d \gset

select public.create_tournament('LB Cup', 20, 2, 2) as _t \gset
select public.add_tournament_team(:'_t'::uuid, :'_a'::uuid, 'A');
select public.add_tournament_team(:'_t'::uuid, :'_b'::uuid, 'B');
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,6,'{"squad_size":2}'::jsonb) as _m \gset
select current_role as _seedrole0 \gset
set local role postgres;
insert into public.tournament_matches(tournament_id, match_id, stage, group_label)
 values (:'_t'::uuid, :'_m'::uuid, 'group', 'A');
set local role :_seedrole0;
select public.start_innings(:'_m'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _i \gset

select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
 values (:'_i'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,6);
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,wicket_type,dismissed_player_id)
 values (:'_i'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,'bowled',:'_s'::uuid);
update public.matches set status = 'complete' where id = :'_m'::uuid;
set local role :_seedrole;

-- 1-3. the answer is unchanged: names still resolve, from the same table
select is(
  (public.tournament_leaderboard(:'_t'::uuid)->'most_runs'->0->>'name'),
  'Striker', 'the leading run scorer is still named');
select is(
  (public.tournament_leaderboard(:'_t'::uuid)->'most_wickets'->0->>'name'),
  'Bowler', 'and so is the leading wicket taker');
select is(
  (public.tournament_leaderboard(:'_t'::uuid)->'most_sixes'->0->>'sixes')::int,
  1, 'the six is counted');

-- 4. and the decoy - a membership with no part in this tournament - is nowhere
--    in the answer, which is the point of scoping the CTE to who appeared.
select is(
  (select count(*)::int
     from jsonb_array_elements(public.tournament_leaderboard(:'_t'::uuid)->'most_runs') e
    where e->>'name' = 'Decoy'),
  0, 'a membership from an unrelated team is not in the leaderboard');

-- 5. The four assertions above hold with or without the fix - the leaderboard
--    only ever listed players who scored - so they guard against the change
--    BREAKING something, not against it being reverted.
--
--    BE HONEST ABOUT WHAT THIS ONE IS. Scoping the CTE changes COST, not output:
--    there is no query whose answer differs, so there is no behavioural proof to
--    write. It is a source assertion, and it has to be a tight one. The first
--    version matched 'join appearing' anywhere in the definition, which review
--    #3 caught: I reverted the CTE to unfiltered, left the phrase behind in a
--    COMMENT, and this file stayed green. Now the join has to be inside the
--    names CTE itself.
select matches(
  (select substring(pg_get_functiondef(p.oid)
                    from 'names as \((.*?)\),\s*run_agg')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'tournament_leaderboard'),
  'join\s+appearing\s+\w+\s+on',
  'the names CTE ITSELF joins the members who appear - not a comment mentioning '
  'it somewhere else in the function');

-- 6. 73: the claim inbox has an index to find pending rows by, instead of
--    seq-scanning the table and calling is_team_admin for every pending claim
--    anyone on the platform has ever filed.
select isnt(
  (select count(*)::int from pg_indexes
    where schemaname = 'public' and tablename = 'guest_claim_requests'
      and indexdef like '%status%'),
  0, 'pending claims are reachable by an index');

-- 7. and the policy hoists auth.uid() into an InitPlan rather than
--    re-evaluating it per row. `(select auth.uid())` is the form the rest of
--    this codebase uses; this one was left as a bare call.
select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and tablename = 'guest_claim_requests'
      and qual like '%( SELECT auth.uid()%'),
  1, 'the policy hoists auth.uid()');

select * from finish();
rollback;
