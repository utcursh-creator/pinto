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

-- Over 1: 5 dots + 1 leg-bye(1) => 6 legal, bowler charged 0 => MAIDEN (leg-byes do not break a maiden). 5 dots.
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,extra_leg_byes) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,3,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,4,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,5,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,6,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,1);
set local role :_seedrole;
-- Over 2: a wide then 6 dots => 6 legal + 1 wide, bowler charged 1 => NOT a maiden. 6 dots.
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,extra_wides) values
 (:'_in'::uuid,7,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,1),
 (:'_in'::uuid,8,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,9,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,10,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,11,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,12,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0),
 (:'_in'::uuid,13,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,0);
set local role :_seedrole;

select is((public.compute_innings_state(:'_in'::uuid)->'bowling'->0->>'maidens')::int, 1, 'one maiden (leg-byes do not break it; the wide-over does)');
select is((public.compute_innings_state(:'_in'::uuid)->'bowling'->0->>'dots')::int, 11, 'dots = 11 (5 + 6)');
select is((public.compute_innings_state(:'_in'::uuid)->'bowling'->0->>'wides_bowled')::int, 1, 'wides_bowled = 1');
select is((public.compute_innings_state(:'_in'::uuid)->'bowling'->0->>'legal_balls')::int, 12, 'legal_balls = 12');
select is(public.compute_innings_state(:'_in'::uuid)->'bowling'->0->>'overs', '2.0', 'overs = 2.0');
select * from finish();
rollback;
