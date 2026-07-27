-- set_delivery_wagon: a scorer attaches a wagon-wheel shot location to a
-- just-recorded delivery (the console records the ball, gets the
-- wagon_applicable hint, then taps the shot).
begin;
select plan(2);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S') as _s \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_b'::uuid,'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

-- a boundary (wagon-applicable) ball
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 4);

-- scoped to OUR innings. `order by seq desc limit 1` over the whole table
-- picked an arbitrary row, and since fold v14 that row can be a non-ball EVENT
-- (strike_swap / retirement) which cannot carry a shot at all.
select id as _d from public.deliveries
  where innings_id = :'_in'::uuid and event_kind is null
  order by seq desc limit 1 \gset

select lives_ok(
  format($$ select public.set_delivery_wagon(%L, 0.7::real, 0.4::real, 3::smallint) $$, :'_d'),
  'scorer can set a wagon location on a delivery');

select is(
  (select wagon_zone from public.deliveries where id = :'_d'::uuid),
  3::smallint,
  'wagon zone persisted');

select * from finish();
rollback;
