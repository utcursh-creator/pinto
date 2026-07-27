begin;
select plan(4);
select tests.create_supabase_user('cap@s.dev');
select tests.create_supabase_user('out@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('Alpha','Pune') as _a \gset
select public.create_team('Beta','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'Striker') as _s \gset
select public.add_guest_member(:'_a'::uuid,'NonStriker') as _ns \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset

select has_table('public','innings','innings table');
select isnt(public.start_innings(:'_mt'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid), null, 'scorer starts innings');
select is((select innings_number from public.innings where match_id = :'_mt'::uuid), 1, 'innings 1 created');

-- non-scorer cannot start an innings
select tests.authenticate_as('out@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('out@s.dev'),'Out');
-- scoped to the match THIS test created (see 25 for why the unscoped form was
-- vacuous even while green).
select throws_ok(
  format($$ select public.start_innings(%L, 2, %L, %L, %L, %L) $$,
    :'_mt', :'_b', :'_a', :'_s', :'_ns'),
  'P0001', 'not authorized', 'non-scorer cannot start an innings');

select * from finish();
rollback;
