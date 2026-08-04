begin;
select plan(10);
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

-- POSITIVE CONTROL FIRST. Every assertion below is about what a probe can and
-- cannot learn ABOUT THIS POST - and all of them hold vacuously if the post is
-- not returned at all. A regression in the radius clamp, the expiry filter or
-- the match-date floor (exactly the class pgTAP 112 exists for) would have made
-- every one of them pass while the oracle they guard was gone
-- (whole-system review #2, finding 81).
select is(
  (select count(*)::int from public.discover_posts(19.076123, 72.877654, 25000)
    where post_id = :'_p'::uuid),
  1, 'CONTROL: the post is actually discoverable - without this every '
     'assertion below passes on an empty result');

-- probing with a tiny radius must not confirm a precise location: the radius is
-- clamped to a 2 km floor, so a 1 m probe behaves exactly like a 2 km probe.
-- Asserting the VALUE, not just that two counts match: 0 = 0 was true with the
-- clamp deleted.
-- Same-cell probe: _snap_geog rounds BOTH the post and the probe onto a
-- 0.005-degree grid (~550 m), so the distance between them is exactly 0 and the
-- radius never enters into it. This is the primary protection, and it is what
-- the next two assertions actually pin.
select is(
  (select count(*)::int from public.discover_posts(19.076123, 72.877654, 1)
    where post_id = :'_p'::uuid),
  1, 'a 1 m probe in the same grid cell still returns the post - snapping, not '
     'the radius, is what defeats a pinpoint probe');
select is(
  (select count(*)::int from public.discover_posts(19.076123, 72.877654, 1)
    where post_id = :'_p'::uuid),
  (select count(*)::int from public.discover_posts(19.076123, 72.877654, 2000)
    where post_id = :'_p'::uuid),
  'and is indistinguishable from a 2 km probe (radius clamped)');

-- THE RADIUS FLOOR, which the same-cell probes above do NOT exercise: a probe
-- three cells away (~1.6 km) asking for a 1 m radius must still see the post,
-- because the radius is floored at 2 km. Without the floor this returns
-- nothing, and an attacker could binary-search the radius to locate somebody
-- to within a cell.
select is(
  (select count(*)::int from public.discover_posts(19.0611, 72.8776, 1)
    where post_id = :'_p'::uuid),
  1, 'a 1 m radius from ~1.6 km away still returns the post - the 2 km floor '
     'stops the radius itself being used as a ruler');

-- the distance is reported COARSELY. The previous assertion here put the
-- IDENTICAL expression on both sides of is(), which holds for any
-- implementation of any deterministic function - it could not fail.
select ok(
  (select approx_m from public.discover_posts(19.0761, 72.8776, 25000)
    where post_id = :'_p'::uuid)::numeric % 100 = 0,
  'the reported distance is snapped to 100 m, so it cannot pinpoint anybody');

-- two probe origins inside the same grid cell must return the SAME distance,
-- so differencing them yields no information. Both sides asserted non-null
-- first: `is not distinct from` is true when both are NULL, which is exactly
-- what an empty result gives.
select isnt(
  (select approx_m from public.discover_posts(19.0762, 72.8777, 25000)
    where post_id = :'_p'::uuid),
  null, 'the second probe returns the post too');
select ok(
  (select approx_m from public.discover_posts(19.0762, 72.8777, 25000)
    where post_id = :'_p'::uuid)
    is not distinct from
  (select approx_m from public.discover_posts(19.0761, 72.8776, 25000)
    where post_id = :'_p'::uuid),
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
