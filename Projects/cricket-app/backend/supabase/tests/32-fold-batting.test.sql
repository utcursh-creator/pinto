begin;
select plan(5);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S') as _s \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_a'::uuid,'X') as _x \gset
select public.add_guest_member(:'_b'::uuid,'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_s'::uuid, 1, false, false);
select public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_ns'::uuid, 2, false, false);
select public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_x'::uuid, 3, false, false);
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

-- S faces: 4, 6, 1 (then swaps to NS); NS faces a dot. X never bats.
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
 (:'_in'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,4),
 (:'_in'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,6),
 (:'_in'::uuid,3,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,1),
 (:'_in'::uuid,4,:'_bw'::uuid,:'_ns'::uuid,:'_s'::uuid,0);

select is((select (b->>'runs')::int from jsonb_array_elements(public.compute_innings_state(:'_in'::uuid)->'batting') b where b->>'batter_id' = (:'_s'::uuid)::text), 11, 'S runs = 11');
select is((select (b->>'balls')::int from jsonb_array_elements(public.compute_innings_state(:'_in'::uuid)->'batting') b where b->>'batter_id' = (:'_s'::uuid)::text), 3, 'S balls = 3');
select is((select (b->>'fours')::int from jsonb_array_elements(public.compute_innings_state(:'_in'::uuid)->'batting') b where b->>'batter_id' = (:'_s'::uuid)::text), 1, 'S fours = 1');
select is((select (b->>'sixes')::int from jsonb_array_elements(public.compute_innings_state(:'_in'::uuid)->'batting') b where b->>'batter_id' = (:'_s'::uuid)::text), 1, 'S sixes = 1');
select is((select count(*)::int from jsonb_array_elements_text(public.compute_innings_state(:'_in'::uuid)->'did_not_bat') e where e = (:'_x'::uuid)::text), 1, 'X is in did_not_bat');
select * from finish();
rollback;
