begin;
select plan(16);
-- SCOR-16: swap_strike + retire_batter are NON-BALL events - they change who is
-- at the crease without consuming a ball, crediting a bowler, or (for retired
-- hurt) costing a wicket. v13 never even applied a retirement's replacement.
select tests.create_supabase_user('ev@e.dev');
select tests.authenticate_as('ev@e.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('ev@e.dev'), 'Ev');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'a1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid, 'a2') as _a2 \gset
select public.add_guest_member(:'_a'::uuid, 'a3') as _a3 \gset
select public.add_guest_member(:'_a'::uuid, 'a4') as _a4 \gset
select public.add_guest_member(:'_b'::uuid, 'bb') as _bb \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_a1'::uuid, :'_a2'::uuid) as _i \gset

-- one single: a2 takes strike
select public.record_ball(:'_i'::uuid, :'_bb'::uuid, 1);
select is(public.compute_innings_state(:'_i'::uuid)->>'striker_id', :'_a2',
  'after a single the non-striker is on strike');

-- manual swap puts a1 back on strike, without consuming a ball
select isnt(public.swap_strike(:'_i'::uuid), null, 'swap_strike records an event');
select is(public.compute_innings_state(:'_i'::uuid)->>'striker_id', :'_a1',
  'swap_strike flips the current pair');
select is(public.compute_innings_state(:'_i'::uuid)->>'over', '0.1',
  'a strike swap is not a ball - the over does not advance');
select is(public.compute_innings_state(:'_i'::uuid)->>'last_seq', '2',
  'fold v14 reports the last event seq as the version token');

-- retired hurt: a1 walks off, a3 comes in; no wicket falls
select isnt(public.retire_batter(:'_i'::uuid, :'_a1'::uuid, false, :'_a3'::uuid), null,
  'retire_batter (hurt) records an event');
select is(public.compute_innings_state(:'_i'::uuid)->>'striker_id', :'_a3',
  'the incoming batter takes the retiring batter''s end');
select is(public.compute_innings_state(:'_i'::uuid)->>'wickets', '0',
  'retired not out costs no wicket');
select is(public.compute_innings_state(:'_i'::uuid)->>'legal_balls', '1',
  'a retirement is not a ball');
select is(
  (select e->>'how_out' from jsonb_array_elements(public.compute_innings_cards(:'_i'::uuid)->'batting') e
    where e->>'member_id' = :'_a1'),
  'retired_not_out', 'the card labels the batter retired not out');
select is(
  (select e->>'dismissed' from jsonb_array_elements(public.compute_innings_cards(:'_i'::uuid)->'batting') e
    where e->>'member_id' = :'_a1'),
  'false', 'retired not out is NOT a dismissal (stats treat it as not out)');
select is(
  (select e->>'legal_balls' from jsonb_array_elements(public.compute_innings_state(:'_i'::uuid)->'bowling') e
    where e->>'bowler_id' = :'_bb'),
  '1', 'the bowler is not charged a ball for a retirement');

-- retired OUT: a3 retires out, a4 in; that IS a wicket
select isnt(public.retire_batter(:'_i'::uuid, :'_a3'::uuid, true, :'_a4'::uuid), null,
  'retire_batter (out) records an event');
select is(public.compute_innings_state(:'_i'::uuid)->>'wickets', '1',
  'retired out counts as a wicket');

-- guards
select throws_ok(
  format($$ select public.retire_batter(%L, %L, false, %L) $$, :'_i', :'_a1', :'_a3'),
  'P0001', 'that batter is not at the crease',
  'cannot retire a batter who is not batting');
select throws_ok(
  format($$ select public.retire_batter(%L, %L, false) $$, :'_i', :'_a4'),
  'P0001', 'an incoming batter is required (this is not the last wicket)',
  'a mid-innings retirement needs the incoming batter');

select * from finish();
rollback;
