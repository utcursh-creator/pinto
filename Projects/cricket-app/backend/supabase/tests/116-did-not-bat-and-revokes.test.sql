begin;
select plan(5);
-- LOW x2 (penetration review 2026-07-07):
--  * did_not_bat was "everyone in the squad who is not in _batters", and
--    _batters only gains an entry when a player FACES a ball. A batter run out
--    backing up at the non-striker's end never faces one, so the scorecard
--    listed a DISMISSED player under "did not bat".
--  * insert_ball was still executable by PUBLIC (i.e. anon) while edit_ball and
--    delete_ball had been revoked.

select tests.create_supabase_user('dnb@s.dev');
select tests.authenticate_as('dnb@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('dnb@s.dev'), 'Dnb');
select public.create_team('DNB A', 'Pune') as _a \gset
select public.create_team('DNB B', 'Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'Striker')  as _s  \gset
select public.add_guest_member(:'_a'::uuid, 'Backer')   as _nk \gset
select public.add_guest_member(:'_a'::uuid, 'Incoming') as _in \gset
select public.add_guest_member(:'_a'::uuid, 'Bench')    as _bn \gset
select public.add_guest_member(:'_b'::uuid, 'Bowler')   as _bw \gset
select public.add_guest_member(:'_b'::uuid, 'Bowler2')  as _bw2 \gset

select public.create_match(:'_a'::uuid, :'_b'::uuid, 5) as _m \gset
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_s'::uuid, 1);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_nk'::uuid, 2);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_in'::uuid, 3);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_bn'::uuid, 4);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_bw'::uuid, 1);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_bw2'::uuid, 2);
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid,
                            :'_s'::uuid, :'_nk'::uuid) as _i \gset

-- ball 1: the NON-STRIKER is run out backing up. He never faced a delivery.
reset role;
insert into public.deliveries(innings_id, seq, bowler_id, striker_id, non_striker_id,
                              runs_off_bat, wicket_type, dismissed_player_id,
                              incoming_batter_id)
values (:'_i'::uuid, 1, :'_bw'::uuid, :'_s'::uuid, :'_nk'::uuid,
        0, 'run_out', :'_nk'::uuid, :'_in'::uuid);
select tests.authenticate_as('dnb@s.dev');

-- 1. THE BUG: a player who was dismissed must never be listed as "did not bat"
select is(
  (select count(*)::int
     from jsonb_array_elements_text(
            public.compute_innings_state(:'_i'::uuid) -> 'did_not_bat') v
    where v = :'_nk'),
  0, 'a batter who was run out is NOT listed as did-not-bat');

-- 2. nor is the striker, who did face one
select is(
  (select count(*)::int
     from jsonb_array_elements_text(
            public.compute_innings_state(:'_i'::uuid) -> 'did_not_bat') v
    where v = :'_s'),
  0, 'the batter who faced a ball is not did-not-bat either');

-- 3. the incoming batter is at the crease now, so he has batted
select is(
  (select count(*)::int
     from jsonb_array_elements_text(
            public.compute_innings_state(:'_i'::uuid) -> 'did_not_bat') v
    where v = :'_in'),
  0, 'the batter who came in is not did-not-bat');

-- 4. the one who really never came in IS listed
select is(
  (select count(*)::int
     from jsonb_array_elements_text(
            public.compute_innings_state(:'_i'::uuid) -> 'did_not_bat') v
    where v = :'_bn'),
  1, 'the player who never came in IS did-not-bat');

-- 5. insert_ball is no longer reachable by anon
select tests.clear_authentication();
select throws_ok(
  format($$ select public.insert_ball(%L, 1, %L, 1, 0, 0, 0, 0, 0, null, null, null, null, null) $$,
         :'_i', :'_bw'),
  '42501', null, 'an anonymous caller cannot execute insert_ball');

select * from finish();
rollback;
