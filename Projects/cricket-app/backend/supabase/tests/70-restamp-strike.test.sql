-- After a correction, deliveries.striker_id/non_striker_id must be re-stamped
-- from the fold so direct readers see the rotation-correct facing batter.
begin;
select plan(4);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_b'::uuid,'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

-- ball 1 = single (S faces, strike rotates -> NS on strike); ball 2 = dot (NS faces)
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 1);
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 0);

-- A) restamp repairs corrupted stamps: corrupt all to the opening pair, then fix.
update public.deliveries set striker_id = :'_s'::uuid, non_striker_id = :'_ns'::uuid
  where innings_id = :'_in'::uuid;
select public.restamp_innings_strike(:'_in'::uuid);
select is(
  (select striker_id from public.deliveries where innings_id = :'_in'::uuid and seq = 2),
  :'_ns'::uuid, 'restamp: ball 2 is faced by the non-striker after a single');

-- B) edit_ball that removes the rotation must re-stamp downstream: ball1 -> dot,
-- so ball 2 is now faced by the original striker.
select public.edit_ball((select id from public.deliveries where innings_id = :'_in'::uuid and seq = 1), 0);
select is(
  (select striker_id from public.deliveries where innings_id = :'_in'::uuid and seq = 2),
  :'_s'::uuid, 'edit_ball re-stamps downstream strike (no rotation -> S still on strike)');

-- C) insert_ball must stamp the inserted ball + downstream from the fold, not the
-- opening pair. Insert a single after ball 1: new seq2 faced by S (rotates), seq3 by NS.
select public.insert_ball(:'_in'::uuid, 1, :'_bw'::uuid, 1);
select is(
  (select striker_id from public.deliveries where innings_id = :'_in'::uuid and seq = 2),
  :'_s'::uuid, 'insert_ball: inserted ball faced by S (not blindly the opening pair)');
select is(
  (select striker_id from public.deliveries where innings_id = :'_in'::uuid and seq = 3),
  :'_ns'::uuid, 'insert_ball re-stamps the shifted ball (NS on strike after the single)');

select * from finish();
rollback;
