begin;
select plan(4);
-- SCOR-2/5 (final audit): the corrections path must not write a mid-innings
-- wicket without the incoming batter (the fold would keep the out batter at the
-- crease). Editing the LAST ball into a wicket without incoming stays legal
-- (the innings ends there), matching the console's last-wicket case.
select tests.create_supabase_user('sc@c.dev');
select tests.authenticate_as('sc@c.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('sc@c.dev'), 'Sc');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'a1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid, 'a2') as _a2 \gset
select public.add_guest_member(:'_a'::uuid, 'a3') as _a3 \gset
select public.add_guest_member(:'_b'::uuid, 'bb') as _bb \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_a1'::uuid, :'_a2'::uuid) as _i \gset

-- three recorded singles
select public.record_ball(:'_i'::uuid, :'_bb'::uuid, 1);
select public.record_ball(:'_i'::uuid, :'_bb'::uuid, 1);
select public.record_ball(:'_i'::uuid, :'_bb'::uuid, 1);

-- editing ball 1 (which has later balls) into a wicket WITHOUT incoming -> refused
select throws_ok(
  format($$ select public.edit_ball(
      (select id from public.deliveries where innings_id = %L and seq = 1),
      _wicket_type := 'bowled', _dismissed_player_id := %L) $$,
    :'_i', :'_a1'),
  'P0001', 'a mid-innings wicket needs the incoming batter',
  'edit_ball refuses a mid-innings wicket without incoming');

-- with the incoming batter named it succeeds
select lives_ok(
  format($$ select public.edit_ball(
      (select id from public.deliveries where innings_id = %L and seq = 1),
      _wicket_type := 'bowled', _dismissed_player_id := %L,
      _incoming_batter_id := %L) $$,
    :'_i', :'_a1', :'_a3'),
  'edit_ball accepts the wicket once incoming is named');

-- inserting a wicket BEFORE later balls without incoming -> refused
select throws_ok(
  format($$ select public.insert_ball(%L, 1, %L, _wicket_type := 'bowled',
      _dismissed_player_id := %L) $$,
    :'_i', :'_bb', :'_a2'),
  'P0001', 'a mid-innings wicket needs the incoming batter',
  'insert_ball refuses a mid-innings wicket without incoming');

-- editing the LAST ball into a wicket without incoming is allowed (innings ends)
select lives_ok(
  format($$ select public.edit_ball(
      (select id from public.deliveries where innings_id = %L
        and seq = (select max(seq) from public.deliveries where innings_id = %L)),
      _wicket_type := 'caught', _dismissed_player_id := %L, _fielder_id := %L) $$,
    :'_i', :'_i', :'_a2', :'_bb'),
  'a wicket on the final ball may omit the incoming batter');

select * from finish();
rollback;
