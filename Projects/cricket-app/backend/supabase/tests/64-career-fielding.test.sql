-- player_career_stats fielding: catches / run-outs / stumpings credited by
-- fielder_id, summed across completed matches. cap (team A) fields while B bats;
-- a different A member bowls so cap's bowling line stays empty.
begin;
select plan(4);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select id as _cap from public.team_members where profile_id = tests.get_supabase_uid('cap@s.dev') and team_id = :'_a'::uuid \gset
select public.add_guest_member(:'_a'::uuid,'Bw2') as _bw \gset
select public.add_guest_member(:'_b'::uuid,'b1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid,'b2') as _b2 \gset
select public.add_guest_member(:'_b'::uuid,'b3') as _b3 \gset
select public.add_guest_member(:'_b'::uuid,'b4') as _b4 \gset
select public.add_guest_member(:'_b'::uuid,'b5') as _b5 \gset
select public.add_guest_member(:'_b'::uuid,'b6') as _b6 \gset

select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m1 \gset
select public.add_squad_member(:'_m1'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_m1'::uuid,1,:'_b'::uuid,:'_a'::uuid,:'_b1'::uuid,:'_b2'::uuid) as _i1 \gset
-- cap catches 2, runs out 1 (the non-striker), stumps 1; bowler is Bw2 throughout
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,fielder_id,incoming_batter_id) values
  (:'_i1'::uuid,1,:'_bw'::uuid,:'_b1'::uuid,:'_b2'::uuid,'caught',:'_cap'::uuid,:'_b3'::uuid),
  (:'_i1'::uuid,2,:'_bw'::uuid,:'_b3'::uuid,:'_b2'::uuid,'caught',:'_cap'::uuid,:'_b4'::uuid);
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,dismissed_player_id,fielder_id,incoming_batter_id) values
  (:'_i1'::uuid,3,:'_bw'::uuid,:'_b4'::uuid,:'_b2'::uuid,'run_out',:'_b2'::uuid,:'_cap'::uuid,:'_b5'::uuid);
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,fielder_id,incoming_batter_id) values
  (:'_i1'::uuid,4,:'_bw'::uuid,:'_b4'::uuid,:'_b5'::uuid,'stumped',:'_cap'::uuid,:'_b6'::uuid);
select public.set_match_result(:'_m1'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);

select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'fielding'->>'catches')::int, 2, 'catches = 2');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'fielding'->>'run_outs')::int, 1, 'run-outs = 1');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'fielding'->>'stumpings')::int, 1, 'stumpings = 1');
-- cap never bowled in this match -> empty bowling line
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'innings')::int, 0, 'no bowling innings (cap only fielded)');

select * from finish();
rollback;
