begin;
select plan(8);
-- SCOR-3: after a run-out, strike must come from the `crossed` flag (did the
-- batters cross on the fatal, incomplete run), not just off-bat run parity.
-- Expected strikers hand-computed per case (S faces, NS at the other end, IN in).
-- (psql lowercases unquoted \gset aliases, so keep var names lowercase.)
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@s.dev'), 'Cap');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid, 'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid, 'IN') as _in \gset
select public.add_guest_member(:'_b'::uuid, 'Bowl') as _bw \gset

-- Case A: striker run out on 0 completed, crossed=false -> IN on strike, NS unchanged.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m1 \gset
select public.start_innings(:'_m1'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i1 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,wicket_type,dismissed_player_id,incoming_batter_id,crossed)
 values (:'_i1'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,'run_out',:'_s'::uuid,:'_in'::uuid,false);
set local role :_seedrole;
select is(public.compute_innings_state(:'_i1'::uuid)->>'striker_id',     (:'_in'::uuid)::text, 'A striker: run out on 0 crossed=false -> incoming on strike');
select is(public.compute_innings_state(:'_i1'::uuid)->>'non_striker_id', (:'_ns'::uuid)::text, 'A non-striker: NS unchanged');

-- Case B: non-striker run out on 0, crossed=false -> S stays on strike, IN to NS end.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m2 \gset
select public.start_innings(:'_m2'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i2 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,wicket_type,dismissed_player_id,incoming_batter_id,crossed)
 values (:'_i2'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,'run_out',:'_ns'::uuid,:'_in'::uuid,false);
set local role :_seedrole;
select is(public.compute_innings_state(:'_i2'::uuid)->>'striker_id',     (:'_s'::uuid)::text,  'B striker: NS run out -> S stays on strike');
select is(public.compute_innings_state(:'_i2'::uuid)->>'non_striker_id', (:'_in'::uuid)::text, 'B non-striker: incoming to the NS end');

-- Case C: striker run out on 1 completed, crossed=false -> NS on strike, IN to NS end.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m3 \gset
select public.start_innings(:'_m3'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i3 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,wicket_type,dismissed_player_id,incoming_batter_id,crossed)
 values (:'_i3'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1,'run_out',:'_s'::uuid,:'_in'::uuid,false);
set local role :_seedrole;
select is(public.compute_innings_state(:'_i3'::uuid)->>'striker_id',     (:'_ns'::uuid)::text, 'C striker: run out on 1 crossed=false -> NS on strike');
select is(public.compute_innings_state(:'_i3'::uuid)->>'non_striker_id', (:'_in'::uuid)::text, 'C non-striker: incoming at the far end');

-- Case D: striker run out on 1 completed, crossed=true -> IN on strike, NS unchanged.
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m4 \gset
select public.start_innings(:'_m4'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _i4 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,wicket_type,dismissed_player_id,incoming_batter_id,crossed)
 values (:'_i4'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1,'run_out',:'_s'::uuid,:'_in'::uuid,true);
set local role :_seedrole;
select is(public.compute_innings_state(:'_i4'::uuid)->>'striker_id',     (:'_in'::uuid)::text, 'D striker: run out on 1 crossed=true -> incoming on strike');
select is(public.compute_innings_state(:'_i4'::uuid)->>'non_striker_id', (:'_ns'::uuid)::text, 'D non-striker: NS at the far end');

select * from finish();
rollback;
