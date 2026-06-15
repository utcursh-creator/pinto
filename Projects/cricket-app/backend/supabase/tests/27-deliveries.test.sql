begin;
select plan(7);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('Alpha','Pune') as _a \gset
select public.create_team('Beta','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S') as _s \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_b'::uuid,'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset
select public.start_innings(:'_mt'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _in \gset

select has_table('public','deliveries','deliveries table');
select col_type_is('public','deliveries','seq','bigint','seq is bigint');
select fk_ok('public','deliveries','innings_id','public','innings','id');
select fk_ok('public','deliveries','striker_id','public','team_members','id');
select has_column('public','deliveries','is_legal','is_legal column');

-- CHECK: a delivery cannot be both a wide and a no-ball
select throws_ok(
  $$ insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,extra_wides,extra_no_ball_penalty)
     values ((select id from public.innings limit 1), 1,
             (select id from public.team_members where guest_name='Bowl'),
             (select id from public.team_members where guest_name='S'),
             (select id from public.team_members where guest_name='NS'), 1, 1) $$,
  '23514', null, 'cannot be both wide and no-ball');

select has_index('public','deliveries','deliveries_innings_seq_uidx','unique (innings_id, seq) index');
select * from finish();
rollback;
