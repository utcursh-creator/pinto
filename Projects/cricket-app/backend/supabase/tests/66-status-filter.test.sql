-- Status policy: averages/aggregates fold COMPLETE matches only; matches-played
-- (Mat) counts complete + abandoned; setup/live are excluded from both (so an
-- anon caller can never reach in-progress data). cap plays a complete match (20),
-- an abandoned match (12), and a live match (50) - only the 20 may count.
begin;
select plan(3);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select id as _cap from public.team_members where profile_id = tests.get_supabase_uid('cap@s.dev') and team_id = :'_a'::uuid \gset
select public.add_guest_member(:'_a'::uuid,'P2') as _p2 \gset
select public.add_guest_member(:'_b'::uuid,'Bw') as _bw \gset

-- COMPLETE: cap 20 (3 sixes + a 2)
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _mc \gset
select public.add_squad_member(:'_mc'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_mc'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _ic \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_ic'::uuid, g, :'_bw'::uuid, :'_cap'::uuid, :'_p2'::uuid, 6 from generate_series(1,3) g;
set local role :_seedrole;
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  values (:'_ic'::uuid,4,:'_bw'::uuid,:'_cap'::uuid,:'_p2'::uuid,2);
set local role :_seedrole;
select public.set_match_result(:'_mc'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);

-- ABANDONED: cap 12 (2 sixes) - counts for Mat but NOT for runs/innings
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _ma \gset
select public.add_squad_member(:'_ma'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_ma'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _ia \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_ia'::uuid, g, :'_bw'::uuid, :'_cap'::uuid, :'_p2'::uuid, 6 from generate_series(1,2) g;
set local role :_seedrole;
select public.set_match_result(:'_ma'::uuid,'abandoned'::public.result_type,null);

-- LIVE (started, no result): cap 50 - excluded from Mat AND from aggregates
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _ml \gset
select public.add_squad_member(:'_ml'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_ml'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _il \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_il'::uuid, g, :'_bw'::uuid, :'_cap'::uuid, :'_p2'::uuid, 6 from generate_series(1,8) g;
set local role :_seedrole;
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  values (:'_il'::uuid,9,:'_bw'::uuid,:'_cap'::uuid,:'_p2'::uuid,2);
set local role :_seedrole;

select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->>'matches')::int, 2, 'Mat = 2 (complete + abandoned; live excluded)');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'innings')::int, 1, 'innings batted = 1 (only the complete match folds)');
select is((public.player_career_stats(tests.get_supabase_uid('cap@s.dev'))->'batting'->>'runs')::int, 20, 'runs = 20 (abandoned 12 + live 50 excluded)');

select * from finish();
rollback;
