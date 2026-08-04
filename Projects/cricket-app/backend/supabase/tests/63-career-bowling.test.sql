-- player_career_stats bowling: wickets/economy/average/SR, BBI (most wickets then
-- fewest runs), 4w bucket = exactly 4, maidens. cap bowls in two completed matches:
-- M1 -> 4/2 off 1 over; M2 -> 2/10 off 1 over. cap is on team A and bowls when B bats.
begin;
select plan(13);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select id as _cap from public.team_members where profile_id = tests.get_supabase_uid('cap@s.dev') and team_id = :'_a'::uuid \gset
select public.add_guest_member(:'_b'::uuid,'b1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid,'b2') as _b2 \gset
select public.add_guest_member(:'_b'::uuid,'b3') as _b3 \gset
select public.add_guest_member(:'_b'::uuid,'b4') as _b4 \gset
select public.add_guest_member(:'_b'::uuid,'b5') as _b5 \gset
select public.add_guest_member(:'_b'::uuid,'b6') as _b6 \gset

-- M1: B bats, cap (A) bowls a 6-ball over: 2 runs, 4 wickets (bowled x3 + caught)
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m1 \gset
select public.add_squad_member(:'_m1'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_m1'::uuid,1,:'_b'::uuid,:'_a'::uuid,:'_b1'::uuid,:'_b2'::uuid) as _i1 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
  (:'_i1'::uuid,1,:'_cap'::uuid,:'_b1'::uuid,:'_b2'::uuid,2);
set local role :_seedrole;
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,incoming_batter_id) values
  (:'_i1'::uuid,2,:'_cap'::uuid,:'_b1'::uuid,:'_b2'::uuid,'bowled',:'_b3'::uuid),
  (:'_i1'::uuid,3,:'_cap'::uuid,:'_b3'::uuid,:'_b2'::uuid,'bowled',:'_b4'::uuid),
  (:'_i1'::uuid,4,:'_cap'::uuid,:'_b4'::uuid,:'_b2'::uuid,'bowled',:'_b5'::uuid);
set local role :_seedrole;
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,incoming_batter_id) values
  (:'_i1'::uuid,5,:'_cap'::uuid,:'_b5'::uuid,:'_b2'::uuid,'caught',:'_b6'::uuid);
set local role :_seedrole;
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
  (:'_i1'::uuid,6,:'_cap'::uuid,:'_b6'::uuid,:'_b2'::uuid,0);
set local role :_seedrole;
select public.set_match_result(:'_m1'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);

-- M2: B bats, cap bowls a 6-ball over: 10 runs, 2 wickets
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m2 \gset
select public.add_squad_member(:'_m2'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_m2'::uuid,1,:'_b'::uuid,:'_a'::uuid,:'_b1'::uuid,:'_b2'::uuid) as _i2 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
  (:'_i2'::uuid,1,:'_cap'::uuid,:'_b1'::uuid,:'_b2'::uuid,6),
  (:'_i2'::uuid,2,:'_cap'::uuid,:'_b1'::uuid,:'_b2'::uuid,4);
set local role :_seedrole;
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,incoming_batter_id) values
  (:'_i2'::uuid,3,:'_cap'::uuid,:'_b1'::uuid,:'_b2'::uuid,'bowled',:'_b3'::uuid),
  (:'_i2'::uuid,4,:'_cap'::uuid,:'_b3'::uuid,:'_b2'::uuid,'bowled',:'_b4'::uuid);
set local role :_seedrole;
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
  (:'_i2'::uuid,5,:'_cap'::uuid,:'_b4'::uuid,:'_b2'::uuid,0),
  (:'_i2'::uuid,6,:'_cap'::uuid,:'_b4'::uuid,:'_b2'::uuid,0);
set local role :_seedrole;
select public.set_match_result(:'_m2'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);

select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'innings')::int, 2, 'bowling innings = 2');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'balls')::int, 12, 'legal balls = 12');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'overs'), '2.0', 'overs = 2.0');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'runs')::int, 12, 'runs conceded = 12');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'wickets')::int, 6, 'wickets = 6 (4 + 2)');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'maidens')::int, 0, 'maidens = 0');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'best_wickets')::int, 4, 'BBI wickets = 4');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'best_runs')::int, 2, 'BBI runs = 2 (4/2)');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'average')::numeric, 2.00, 'average = 12/6');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'economy')::numeric, 6.00, 'economy = 12 / (12/6)');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'strike_rate')::numeric, 2.00, 'strike rate = 12/6');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'four_wickets')::int, 1, 'one four-wicket haul (exactly 4)');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'bowling'->>'five_wickets')::int, 0, 'no five-wicket hauls');

select * from finish();
rollback;
