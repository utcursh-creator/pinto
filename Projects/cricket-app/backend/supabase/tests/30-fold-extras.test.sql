begin;
select plan(5);
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

-- one bowler, six deliveries exercising every extra:
-- 1: wide + 1 run run (extra_wides=2)            team+2  bowler+2  not legal
-- 2: no-ball + 4 off the bat                     team+5  bowler+5  not legal  bat+4
-- 3: no-ball + 2 byes                            team+3  bowler+1 (penalty only) not legal
-- 4: bye 1                                        team+1  bowler+0  legal
-- 5: leg-bye 3                                    team+3  bowler+0  legal
-- 6: dot                                          team+0  bowler+0  legal
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,extra_wides,extra_no_ball_penalty,extra_byes,extra_leg_byes,noball_secondary_kind) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,2,0,0,0,null),
 (:'_in'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,4,0,1,0,0,'off_bat'),
 (:'_in'::uuid,3,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0,1,2,0,'bye'),
 (:'_in'::uuid,4,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0,0,1,0,null),
 (:'_in'::uuid,5,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0,0,0,3,null),
 (:'_in'::uuid,6,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0,0,0,0,null);
set local role :_seedrole;

select is((public.compute_innings_state(:'_in'::uuid)->>'runs')::int, 14, 'team runs = 14');
select is((public.compute_innings_state(:'_in'::uuid)->>'legal_balls')::int, 3, 'legal_balls = 3 (wide + 2 no-balls excluded)');
select is((public.compute_innings_state(:'_in'::uuid)->'extras'->>'byes')::int, 3, 'byes = 3 (2 off the no-ball + 1)');
select is((public.compute_innings_state(:'_in'::uuid)->'extras'->>'no_balls')::int, 2, 'no_balls = 2');
select is((public.compute_innings_state(:'_in'::uuid)->'bowling'->0->>'runs_conceded')::int, 8, 'bowler conceded = 8 (byes/leg-byes never charged)');
select * from finish();
rollback;
