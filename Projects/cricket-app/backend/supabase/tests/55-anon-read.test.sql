begin;
select plan(8);

select tests.create_supabase_user('sc@m.dev');
select tests.create_supabase_user('mt@m.dev');
select tests.authenticate_as('sc@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('sc@m.dev'),'Sc');
select tests.authenticate_as('mt@m.dev'); insert into public.profiles(id,display_name) values (tests.get_supabase_uid('mt@m.dev'),'Mt');

-- sc captains team A and an UNRELATED team C; mt captains team B
select tests.authenticate_as('sc@m.dev');
select public.create_team('Team A') as _ta \gset
select public.create_team('Team C') as _tc \gset
select tests.authenticate_as('mt@m.dev');
select public.create_team('Team B') as _tb \gset

-- sc creates the match (A vs B) and a squad with a registered member + a guest
select tests.authenticate_as('sc@m.dev');
select public.create_match(:'_ta'::uuid, :'_tb'::uuid, 20) as _m \gset
select public.add_guest_member(:'_ta'::uuid, 'Guest Gary') as _g \gset
select id as _scm from public.team_members where team_id = :'_ta'::uuid and profile_id = tests.get_supabase_uid('sc@m.dev') \gset
select public.add_squad_member(:'_m'::uuid, :'_ta'::uuid, :'_scm'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_ta'::uuid, :'_g'::uuid);

-- match goes live
reset role;  -- fixture setup: this write is no longer granted to clients
update public.matches set status='live' where id = :'_m'::uuid;
select tests.authenticate_as('sc@m.dev');

-- ANON
select tests.clear_authentication();
select is((select count(*)::int from public.matches where id = :'_m'::uuid), 1, 'anon sees a live match');
select is((select count(*)::int from public.match_squad where match_id = :'_m'::uuid), 2, 'anon sees the live match squad');
select is((select guest_name from public.team_members where id = :'_g'::uuid), 'Guest Gary', 'anon resolves a guest player name');
select is((select count(*)::int from public.teams where id in (:'_ta'::uuid, :'_tb'::uuid)), 2, 'anon sees both participating teams');
select is((select count(*)::int from public.teams where id = :'_tc'::uuid), 0, 'anon cannot see an unrelated team');

-- revert to setup -> everything becomes invisible to anon
select tests.authenticate_as('sc@m.dev');
reset role;  -- fixture setup: this write is no longer granted to clients
update public.matches set status='setup' where id = :'_m'::uuid;
select tests.authenticate_as('sc@m.dev');
select tests.clear_authentication();
select is((select count(*)::int from public.matches where id = :'_m'::uuid), 0, 'anon cannot see a setup match');
select is((select count(*)::int from public.match_squad where match_id = :'_m'::uuid), 0, 'anon cannot see a setup match squad');
select is((select count(*)::int from public.team_members where id = :'_g'::uuid), 0, 'anon cannot resolve squad members of a setup match');

select * from finish();
rollback;
