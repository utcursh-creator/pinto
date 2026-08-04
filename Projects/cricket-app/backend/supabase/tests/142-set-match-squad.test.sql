begin;
select plan(11);
-- Whole-system review #2 (2026-07-28), findings 10 and 25 (both HIGH): there is
-- no way to take a player OUT of a match squad, and a half-written squad cannot
-- be repaired.
--
-- The screen writes the XI one row at a time with add_squad_member, which is
-- additive and idempotent. Un-ticking someone only changes a local Set. So:
--
--   * un-ticking a saved player is cosmetic. He stays in match_squad, keeps
--     appearing in the toss screen's opening pair, in the console's batter,
--     bowler and fielder pickers, and on the public scorecard - and the moment
--     a ball is credited to him, player_career_stats bakes a permanent public
--     career record for a man who never played.
--   * the loop is not atomic. If the 8th of 12 writes fails the screen says
--     "Could not save the squads", implying nothing was saved, while 7 rows are
--     already committed. Adjusting the XI and trying again cannot undo them.
--   * the new selection is renumbered 1..N while the abandoned row keeps its
--     old batting_order, so two rows share a slot and the scorecard order is
--     whatever Postgres returns.
--
-- set_match_squad states the WHOLE squad in one transaction: what is not in the
-- list is not in the squad.

select tests.create_supabase_user('cap@sq.dev');
select tests.authenticate_as('cap@sq.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@sq.dev'),'Cap');
select public.create_team('Squad A','Pune') as _a \gset
select public.create_team('Squad B','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'A1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid,'A2') as _a2 \gset
select public.add_guest_member(:'_a'::uuid,'A3') as _a3 \gset
select public.add_guest_member(:'_b'::uuid,'B1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid,'B2') as _b2 \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m \gset

-- the first save: two a side
select public.set_match_squad(:'_m'::uuid, format($j$[
  {"team_id":"%s","team_member_id":"%s","is_captain":true},
  {"team_id":"%s","team_member_id":"%s"},
  {"team_id":"%s","team_member_id":"%s","is_keeper":true},
  {"team_id":"%s","team_member_id":"%s"}
]$j$, :'_a', :'_a1', :'_a', :'_a2', :'_b', :'_b1', :'_b', :'_b2')::jsonb);

select is((select count(*)::int from public.match_squad where match_id = :'_m'::uuid),
  4, 'the squad is saved');
select is((select count(*)::int from public.match_squad
            where match_id = :'_m'::uuid and is_captain), 1,
  'and the captain flag came with it');

-- THE BUG: A2 cannot make it, A3 takes his place
select public.set_match_squad(:'_m'::uuid, format($j$[
  {"team_id":"%s","team_member_id":"%s","is_captain":true},
  {"team_id":"%s","team_member_id":"%s"},
  {"team_id":"%s","team_member_id":"%s","is_keeper":true},
  {"team_id":"%s","team_member_id":"%s"}
]$j$, :'_a', :'_a1', :'_a', :'_a3', :'_b', :'_b1', :'_b', :'_b2')::jsonb);

select is((select count(*)::int from public.match_squad
            where match_id = :'_m'::uuid and team_member_id = :'_a2'::uuid),
  0, 'the player who was dropped is OUT of the squad - un-ticking him was '
     'purely cosmetic before, so he kept turning up in the opening-pair '
     'dropdown, the fielder picker and the public scorecard');
select is((select count(*)::int from public.match_squad
            where match_id = :'_m'::uuid and team_member_id = :'_a3'::uuid),
  1, 'and his replacement is IN');
select is((select count(*)::int from public.match_squad where match_id = :'_m'::uuid),
  4, 'the squad is still four, not five');

-- batting_order is contiguous per side and unique - two rows sharing a slot
-- made the scorecard order arbitrary
select is(
  (select array_agg(batting_order order by batting_order)
     from public.match_squad where match_id = :'_m'::uuid and team_id = :'_a'::uuid),
  array[1,2], 'each side is numbered 1..N with no duplicate slot');

-- 7-8. CONTROL: a bad member is REFUSED, and refused completely.
--
--    Note what this does and does not prove. Inside one transaction Postgres
--    rolls back for free, so no ordering of the guards inside this function
--    could make assertion 8 fail. The atomicity that was actually missing is
--    client-side - twelve separate round-trips, each its own transaction - and
--    that half is pinned by the widget test (one call, not a loop), not here.
--    What these two do pin is that the refusal is a raised error rather than a
--    silently skipped row.
select throws_ok(
  format($$ select public.set_match_squad(%L, '[
    {"team_id":"%s","team_member_id":"%s"},
    {"team_id":"%s","team_member_id":"%s"}
  ]'::jsonb) $$, :'_m', :'_a', :'_a1', :'_a', :'_b1'),
  'P0001', 'that player is not in that team',
  'a member who is not on that roster is refused');
select is((select count(*)::int from public.match_squad where match_id = :'_m'::uuid),
  4, 'and the squad that was already saved is untouched - the failed call '
     'wrote nothing at all');

-- 9. CONTROL: a player who has actually PLAYED cannot be erased. Removing him
--    would orphan his deliveries and rewrite a real scorecard.
select public.start_innings(:'_m'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_a1'::uuid,:'_a3'::uuid) as _i \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
 values (:'_i'::uuid,1,:'_b1'::uuid,:'_a1'::uuid,:'_a3'::uuid,4);
set local role :_seedrole;
select throws_ok(
  format($$ select public.set_match_squad(%L, '[
    {"team_id":"%s","team_member_id":"%s"},
    {"team_id":"%s","team_member_id":"%s"},
    {"team_id":"%s","team_member_id":"%s"}
  ]'::jsonb) $$, :'_m', :'_a', :'_a3', :'_b', :'_b1', :'_b', :'_b2'),
  'P0001', 'that player has already played in this match',
  'a player with deliveries to his name cannot be dropped from the squad');

-- 10. CONTROL: a team that is not in this match is refused
select throws_ok(
  format($$ select public.set_match_squad(%L, '[
    {"team_id":"%s","team_member_id":"%s"}
  ]'::jsonb) $$, :'_m', :'_b', :'_a1'),
  'P0001', 'that player is not in that team',
  'a player cannot be entered under the wrong team');

-- 11. CONTROL: only the scorer
select tests.create_supabase_user('rando@sq.dev');
select tests.authenticate_as('rando@sq.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rando@sq.dev'),'R');
select throws_ok(
  format($$ select public.set_match_squad(%L, '[]'::jsonb) $$, :'_m'),
  'P0001', 'not authorized',
  'a stranger cannot rewrite a match squad');

select * from finish();
rollback;
