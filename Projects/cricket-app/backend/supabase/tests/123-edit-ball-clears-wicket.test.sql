begin;
select plan(5);
-- HIGH (whole-system review #2): a mis-tapped wicket could never be taken back.
-- edit_ball is COALESCE-patch shaped, so omitting _wicket_type KEEPS the
-- existing dismissal; the RPC has an explicit _clear_wicket flag and the Flutter
-- client never sent it. Turning "Wicket" off in the ball-log editor was a silent
-- no-op and the batter stayed out on the scorecard permanently.
-- This pins the SERVER half of the contract the client now relies on.
select tests.create_supabase_user('edit@w.dev');
select tests.authenticate_as('edit@w.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('edit@w.dev'), 'Ed');
select public.create_team('Edit A', 'Pune') as _a \gset
select public.create_team('Edit B', 'Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'A1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid, 'A2') as _a2 \gset
select public.add_guest_member(:'_a'::uuid, 'A3') as _a3 \gset
select public.add_guest_member(:'_b'::uuid, 'B1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid, 'B2') as _b2 \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 5) as _m \gset
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_a1'::uuid, 1);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_a2'::uuid, 2);
select public.add_squad_member(:'_m'::uuid, :'_a'::uuid, :'_a3'::uuid, 3);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_b1'::uuid, 1);
select public.add_squad_member(:'_m'::uuid, :'_b'::uuid, :'_b2'::uuid, 2);
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid,
                            :'_a1'::uuid, :'_a2'::uuid) as _i \gset

-- a wicket is recorded by mistake
select public.record_ball(_innings_id := :'_i'::uuid, _bowler_id := :'_b1'::uuid,
  _wicket_type := 'bowled'::public.wicket_type,
  _dismissed_player_id := :'_a1'::uuid,
  _incoming_batter_id := :'_a3'::uuid);
select id as _ball from public.deliveries where innings_id = :'_i'::uuid order by seq desc limit 1 \gset

select is((select wicket_type::text from public.deliveries where id = :'_ball'::uuid),
  'bowled', 'the mistaken wicket is on the ball');
select is((public.compute_innings_state(:'_i'::uuid)->>'wickets')::int, 1,
  'and the innings counts it');

-- 3. omitting _wicket_type must NOT clear it (that is the patch semantics the
-- client wrongly relied on)
select public.edit_ball(_delivery_id := :'_ball'::uuid, _runs_off_bat := 1);
select is((select wicket_type::text from public.deliveries where id = :'_ball'::uuid),
  'bowled', 'a patch that omits the wicket KEEPS it - this is why a flag is needed');

-- 4-5. the explicit flag clears it, and the fold agrees
select public.edit_ball(_delivery_id := :'_ball'::uuid, _clear_wicket := true);
select is((select wicket_type from public.deliveries where id = :'_ball'::uuid), null,
  '_clear_wicket removes the dismissal');
select is((public.compute_innings_state(:'_i'::uuid)->>'wickets')::int, 0,
  'and the batter is no longer out in the recomputed innings');

select * from finish();
rollback;
