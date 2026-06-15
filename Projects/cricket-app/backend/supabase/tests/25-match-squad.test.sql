begin;
select plan(4);
select tests.create_supabase_user('cap@s.dev');
select tests.create_supabase_user('out@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('Alpha','Pune') as _a \gset
select public.create_team('Beta','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'Guest A1') as _m \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _mt \gset

select has_table('public','match_squad','match_squad table');
select isnt(public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_m'::uuid, 1, false, false), null, 'scorer adds squad member');
select is((select batting_order from public.match_squad where match_id = :'_mt'::uuid and team_member_id = :'_m'::uuid), 1, 'batting order stored');

-- non-scorer cannot add to the squad
select tests.authenticate_as('out@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('out@s.dev'),'Out');
select throws_ok(
  $$ select public.add_squad_member(
       (select id from public.matches limit 1),
       (select team_a_id from public.matches limit 1),
       (select id from public.team_members where guest_name = 'Guest A1'),
       2, false, false) $$,
  'P0001', 'not authorized', 'non-scorer cannot add squad member');

select * from finish();
rollback;
