-- Regression: the consecutive-over guard must not false-positive when a new
-- over's FIRST ball is a wide and the same (new) bowler continues the over.
begin;
select plan(3);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S') as _s \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_b'::uuid,'Bowl1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid,'Bowl2') as _b2 \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

-- over 1: six legal dot balls by Bowl1 (over complete)
select public.record_ball(:'_in'::uuid, :'_b1'::uuid, 0);
select public.record_ball(:'_in'::uuid, :'_b1'::uuid, 0);
select public.record_ball(:'_in'::uuid, :'_b1'::uuid, 0);
select public.record_ball(:'_in'::uuid, :'_b1'::uuid, 0);
select public.record_ball(:'_in'::uuid, :'_b1'::uuid, 0);
select public.record_ball(:'_in'::uuid, :'_b1'::uuid, 0);

-- (preserved) the same bowler still cannot bowl two overs in a row
select throws_ok(
  format($$ select public.record_ball(%L, %L, 0) $$, :'_in', :'_b1'),
  'P0001', 'bowler cannot bowl consecutive overs',
  'same bowler bowling consecutive overs is still rejected');

-- a DIFFERENT bowler may start the new over with a wide (the boundary ball)
select lives_ok(
  format($$ select public.record_ball(%L, %L, 0, 1) $$, :'_in', :'_b2'),
  'new over may start with a wide (different bowler)');

-- ...and may then bowl a legal ball even though the legal-ball count is still a
-- multiple of balls_per_over (the false-positive that used to reject this).
select lives_ok(
  format($$ select public.record_ball(%L, %L, 1) $$, :'_in', :'_b2'),
  'continuing the new over after a wide is allowed');

select * from finish();
rollback;
