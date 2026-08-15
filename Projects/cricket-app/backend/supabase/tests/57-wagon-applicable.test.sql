begin;
select plan(12);

select tests.create_supabase_user('wag@s.dev');
select tests.authenticate_as('wag@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('wag@s.dev'),'Wag');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid,'I1') as _i1 \gset
select public.add_guest_member(:'_a'::uuid,'I2') as _i2 \gset
select public.add_guest_member(:'_a'::uuid,'I3') as _i3 \gset
select public.add_guest_member(:'_a'::uuid,'I4') as _i4 \gset
select public.add_guest_member(:'_a'::uuid,'I5') as _i5 \gset
select public.add_guest_member(:'_b'::uuid,'BW') as _bw \gset
-- allow_consecutive_overs so a single bowler can bowl the whole non-wicket phase
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,6,'{"allow_consecutive_overs": true}'::jsonb) as _mt \gset

-- innings 1: non-wicket cases (S/NS stay on the crease throughout)
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in1 \gset
select is((select wagon_applicable from public.record_ball(:'_in1'::uuid,:'_bw'::uuid,4)), true,  'off-bat four is wagon-applicable');
-- CHANGED 2026-08-05 (journey map C1). This used to assert TRUE, describing what
-- the code did rather than what a scorer wants. The user - who actually scores
-- gully cricket - reported the dot-ball behaviour as wrong, and he is right: a
-- dot is the most common outcome in the game, so prompting "where did 0 runs
-- go?" put a modal in front of the scorer on the majority of deliveries. The
-- old journeys hid it behind a helper that dismissed the sheet after every tap.
select is((select wagon_applicable from public.record_ball(:'_in1'::uuid,:'_bw'::uuid,0)), false, 'a defended dot is NOT wagon-applicable - the ball went nowhere');
select is((select wagon_applicable from public.record_ball(:'_in1'::uuid,:'_bw'::uuid,0,1)), false, 'a wide is not wagon-applicable');
select is((select wagon_applicable from public.record_ball(:'_in1'::uuid,:'_bw'::uuid,0,0,0,1)), false, 'a bye is not wagon-applicable');
select is((select wagon_applicable from public.record_ball(:'_in1'::uuid,:'_bw'::uuid,0,0,0,0,1)), false, 'a leg-bye is not wagon-applicable');
select is((select wagon_applicable from public.record_ball(:'_in1'::uuid,:'_bw'::uuid,2,0,1,0,0,0,'off_bat')), true,  'a no-ball hit off the bat is wagon-applicable');
select is((select wagon_applicable from public.record_ball(:'_in1'::uuid,:'_bw'::uuid,0,0,1,2,0,0,'bye')), false, 'a no-ball that ran byes is not wagon-applicable');

-- each wicket case as ball 1 of a fresh innings (striker is deterministically S)
select public.start_innings(:'_mt'::uuid,2,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in2 \gset
select is((select wagon_applicable from public.record_ball(:'_in2'::uuid,:'_bw'::uuid,0,0,0,0,0,0,null,'bowled',:'_s'::uuid,:'_i1'::uuid)), false, 'bowled is not wagon-applicable');
select public.start_innings(:'_mt'::uuid,3,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in3 \gset
select is((select wagon_applicable from public.record_ball(:'_in3'::uuid,:'_bw'::uuid,0,0,0,0,0,0,null,'caught',:'_s'::uuid,:'_i2'::uuid)), true,  'caught is wagon-applicable');
select public.start_innings(:'_mt'::uuid,4,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in4 \gset
select is((select wagon_applicable from public.record_ball(:'_in4'::uuid,:'_bw'::uuid,1,0,0,0,0,0,null,'run_out',:'_s'::uuid,:'_i3'::uuid)), true,  'a run-out off the bat is wagon-applicable');
select public.start_innings(:'_mt'::uuid,5,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in5 \gset
select is((select wagon_applicable from public.record_ball(:'_in5'::uuid,:'_bw'::uuid,0,1,0,0,0,0,null,'run_out',:'_s'::uuid,:'_i4'::uuid)), false, 'a run-out off a wide is not wagon-applicable');
select public.start_innings(:'_mt'::uuid,6,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in6 \gset
select is((select wagon_applicable from public.record_ball(:'_in6'::uuid,:'_bw'::uuid,0,0,0,0,0,0,null,'stumped',:'_s'::uuid,:'_i5'::uuid)), false, 'stumped is not wagon-applicable');

select * from finish();
rollback;
