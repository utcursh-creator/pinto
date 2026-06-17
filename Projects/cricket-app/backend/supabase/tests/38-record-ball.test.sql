begin;
select plan(4);
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

-- record a legal single
select isnt((select delivery_id from public.record_ball(:'_in'::uuid, :'_bw'::uuid, 1)), null, 'record_ball returns a delivery id');
select is((select count(*)::int from public.deliveries where innings_id = :'_in'::uuid), 1, 'one delivery recorded');
select is((select striker_id from public.deliveries where innings_id = :'_in'::uuid and seq = 1)::text, (:'_s'::uuid)::text, 'striker stamped from the fold (opening striker)');

-- record a no-ball (sets the free hit), then a stumped on the free hit must be REJECTED
select public.record_ball(:'_in'::uuid, :'_bw'::uuid, 0, 0, 1);
select throws_ok(
  $$ select public.record_ball((select id from public.innings limit 1),
       (select id from public.team_members where guest_name='Bowl'),
       0,0,0,0,0,0,null,'stumped') $$,
  'P0001', 'illegal dismissal on a no-ball/free-hit', 'stumped on a free hit is rejected');
select * from finish();
rollback;
