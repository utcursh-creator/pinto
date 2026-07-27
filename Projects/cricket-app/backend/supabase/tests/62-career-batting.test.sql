-- player_career_stats batting: aggregates across COMPLETE matches, not-out-aware
-- HS + average, strike rate, milestones. cap scores 50* in M1 and 30-out in M2.
-- balls_per_over=50 keeps cap on strike (even-run scoring, no over-end swap).
begin;
select plan(13);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select id as _cap from public.team_members where profile_id = tests.get_supabase_uid('cap@s.dev') and team_id = :'_a'::uuid \gset
select public.add_guest_member(:'_a'::uuid,'P2') as _p2 \gset
select public.add_guest_member(:'_a'::uuid,'P3') as _p3 \gset
select public.add_guest_member(:'_b'::uuid,'Bw') as _bw \gset

-- M1: cap 50 not out (8 sixes + a two)
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _m1 \gset
select public.add_squad_member(:'_m1'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_m1'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _i1 \gset
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_i1'::uuid, g, :'_bw'::uuid, :'_cap'::uuid, :'_p2'::uuid, 6 from generate_series(1,8) g;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  values (:'_i1'::uuid,9,:'_bw'::uuid,:'_cap'::uuid,:'_p2'::uuid,2);
select public.set_match_result(:'_m1'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);

-- M2: cap 30 then bowled (5 sixes + a wicket ball)
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _m2 \gset
select public.add_squad_member(:'_m2'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_m2'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _i2 \gset
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_i2'::uuid, g, :'_bw'::uuid, :'_cap'::uuid, :'_p2'::uuid, 6 from generate_series(1,5) g;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,incoming_batter_id)
  values (:'_i2'::uuid,6,:'_bw'::uuid,:'_cap'::uuid,:'_p2'::uuid,'bowled',:'_p3'::uuid);
select public.set_match_result(:'_m2'::uuid,'win_by_runs'::public.result_type,:'_b'::uuid);

select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->>'matches')::int, 2, 'matches played = 2');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'innings')::int, 2, 'innings batted = 2');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'not_outs')::int, 1, 'not outs = 1');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'runs')::int, 80, 'runs = 80');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'balls')::int, 15, 'balls = 15');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'highest')::int, 50, 'highest = 50');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'highest_not_out')::boolean, true, 'highest was not out (50*)');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'average')::numeric, 80.00, 'average = runs / outs = 80');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'strike_rate')::numeric, 533.33, 'strike rate = 100*80/15');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'fifties')::int, 1, 'one fifty');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'hundreds')::int, 0, 'no hundreds');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'ducks')::int, 0, 'no ducks');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'sixes')::int, 13, '13 sixes (8 + 5)');

select * from finish();
rollback;
