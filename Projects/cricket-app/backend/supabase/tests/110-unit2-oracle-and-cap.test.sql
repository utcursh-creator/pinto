begin;
select plan(6);
-- HIGH batch 3 (penetration review 2026-07-07): the location oracle and the
-- bowler cap that can make an innings unfinishable.

select tests.create_supabase_user('oc@o.dev');
select tests.authenticate_as('oc@o.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('oc@o.dev'), 'Oc');

-- 1. LOCATION ORACLE: the true point must never drive the query path.
select public.create_looking_for_post(
  'player_seeking_team'::public.lf_mode, 'practice_match'::public.lf_flair,
  19.076123, 72.877654) as _p \gset

-- the stored coarse point is snapped to the grid, not the exact position
select ok(
  extensions.st_distance(
    (select geog from public.looking_for_posts where id = :'_p'::uuid),
    (select geog_coarse from public.looking_for_posts where id = :'_p'::uuid)) > 0,
  'the coarse point is not the true point');

-- probing with a tiny radius must not confirm a precise location: the radius is
-- clamped to a 2 km floor, so a 1 m probe behaves exactly like a 2 km probe.
select is(
  (select count(*)::int from public.discover_posts(19.076123, 72.877654, 1)
    where post_id = :'_p'::uuid),
  (select count(*)::int from public.discover_posts(19.076123, 72.877654, 2000)
    where post_id = :'_p'::uuid),
  'a 1 m probe is indistinguishable from a 2 km probe (radius clamped)');

-- two probe origins inside the same grid cell must return the SAME distance,
-- so differencing them yields no information
select is(
  (select approx_m from public.discover_posts(19.0761, 72.8776, 25000) where post_id = :'_p'::uuid),
  (select approx_m from public.discover_posts(19.0761, 72.8776, 25000) where post_id = :'_p'::uuid),
  'the reported distance is stable for a given probe');

select ok(
  (select approx_m from public.discover_posts(19.0762, 72.8777, 25000) where post_id = :'_p'::uuid)
    is not distinct from
  (select approx_m from public.discover_posts(19.0761, 72.8776, 25000) where post_id = :'_p'::uuid),
  'probes within one grid cell cannot be differentiated');

-- 2. BOWLER CAP must never make the innings unfinishable: a 5-over match whose
--    bowling squad has only 2 players needs a cap of at least 3.
select public.create_team('Cap A', 'P') as _a \gset
select public.create_team('Cap B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'a1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid, 'a2') as _a2 \gset
select public.add_guest_member(:'_b'::uuid, 'b1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid, 'b2') as _b2 \gset
-- the app stamps ceil(5/5) = 1, which 2 bowlers cannot cover for 5 overs
select public.create_match(:'_a'::uuid, :'_b'::uuid, 5, 6,
  '{"max_overs_per_bowler": 1}'::jsonb) as _m \gset
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_a1'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_a2'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_b1'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_b2'::uuid);
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_a1'::uuid, :'_a2'::uuid) as _i \gset

select is(public._bowler_over_cap(:'_i'::uuid), 3,
  'the enforced cap rises to what the real bowling squad can cover');

-- and the innings is actually completable: 5 overs alternating 2 bowlers
select lives_ok(
  format($$ do $x$
    declare _bw uuid[]; _o int; _k int;
    begin
      select array_agg(ms.team_member_id) into _bw from public.match_squad ms
        join public.innings i on i.id = %L
       where ms.match_id = i.match_id and ms.team_id = i.bowling_team_id;
      for _o in 0..4 loop
        for _k in 1..6 loop
          perform public.record_ball(%L, _bw[(_o %% 2) + 1], 0);
        end loop;
      end loop;
    end $x$; $$, :'_i', :'_i'),
  'all 5 overs can be bowled - the innings is finishable');

select * from finish();
rollback;
