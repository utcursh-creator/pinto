-- Integration: a match recorded through the real record_ball path, completed,
-- then corrected via edit_ball + insert_ball. Career stats re-fold at read time,
-- so they must track the corrected truth with no stored-snapshot to go stale.
-- balls_per_over=50 keeps cap on strike (even-run scoring).
begin;
select plan(6);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select tests.get_supabase_uid('cap@s.dev') as _uid \gset
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select id as _cap from public.team_members where profile_id = :'_uid'::uuid and team_id = :'_a'::uuid \gset
select public.add_guest_member(:'_a'::uuid,'P2') as _p2 \gset
select public.add_guest_member(:'_b'::uuid,'Bw') as _bw \gset

select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _m \gset
select public.add_squad_member(:'_m'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_m'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _in \gset
-- cap scores three fours via the real append path
select public.record_ball(:'_in'::uuid,:'_bw'::uuid,4);
select public.record_ball(:'_in'::uuid,:'_bw'::uuid,4);
select public.record_ball(:'_in'::uuid,:'_bw'::uuid,4);
select public.set_match_result(:'_m'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);

select is((public.player_career_stats(:'_uid'::uuid)->'batting'->>'runs')::int, 12, 'recorded: 12 runs');
select is((public.player_career_stats(:'_uid'::uuid)->'batting'->>'fours')::int, 3, 'recorded: 3 fours');

-- correction A: edit ball 1 from a four to a six
select id as _d1 from public.deliveries where innings_id = :'_in'::uuid and seq = 1 \gset
select public.edit_ball(:'_d1'::uuid, 6);
select is((public.player_career_stats(:'_uid'::uuid)->'batting'->>'runs')::int, 14, 'after edit_ball (4 -> 6): 14 runs');
select is((public.player_career_stats(:'_uid'::uuid)->'batting'->>'sixes')::int, 1, 'after edit_ball: 1 six, 2 fours');

-- correction B: insert a two after ball 1
select public.insert_ball(:'_in'::uuid, 1, :'_bw'::uuid, 2);
select is((public.player_career_stats(:'_uid'::uuid)->'batting'->>'runs')::int, 16, 'after insert_ball (+2): 16 runs');
select is((public.player_career_stats(:'_uid'::uuid)->'batting'->>'balls')::int, 4, 'after insert_ball: 4 balls faced');

select * from finish();
rollback;
