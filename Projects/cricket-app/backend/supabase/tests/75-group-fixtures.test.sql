-- generate_group_fixtures: round-robin within each group -> a matches row +
-- tournament_matches link per pairing; status flips to group_stage; idempotent.
begin;
select plan(7);
select tests.create_supabase_user('org@s.dev');
select tests.create_supabase_user('rando@s.dev');
select tests.authenticate_as('org@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('org@s.dev'),'Org');

select public.create_tournament('Cup', 20, 2, 2) as _t \gset
-- group A: 3 teams, group B: 3 teams
select public.create_team('A1','C') as _a1 \gset
select public.create_team('A2','C') as _a2 \gset
select public.create_team('A3','C') as _a3 \gset
select public.create_team('B1','C') as _b1 \gset
select public.create_team('B2','C') as _b2 \gset
select public.create_team('B3','C') as _b3 \gset
select public.add_tournament_team(:'_t'::uuid, :'_a1'::uuid, 'A');
select public.add_tournament_team(:'_t'::uuid, :'_a2'::uuid, 'A');
select public.add_tournament_team(:'_t'::uuid, :'_a3'::uuid, 'A');
select public.add_tournament_team(:'_t'::uuid, :'_b1'::uuid, 'B');
select public.add_tournament_team(:'_t'::uuid, :'_b2'::uuid, 'B');
select public.add_tournament_team(:'_t'::uuid, :'_b3'::uuid, 'B');

-- a non-organizer cannot generate fixtures (tournament still in setup)
select tests.authenticate_as('rando@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rando@s.dev'),'Rando');
select throws_ok($$ select public.generate_group_fixtures(
  (select id from public.tournaments where name='Cup')) $$,
  'P0001', null, 'a non-organizer cannot generate fixtures');

select tests.authenticate_as('org@s.dev');
select public.generate_group_fixtures(:'_t'::uuid);

select is((select count(*)::int from public.tournament_matches where tournament_id=:'_t'::uuid),
  6, 'C(3,2)=3 matches per group -> 6 fixtures');
select is((select count(*)::int from public.tournament_matches
           where tournament_id=:'_t'::uuid and group_label='A' and stage='group'), 3,
  'group A has 3 group fixtures');
select is((select count(*)::int from public.tournament_matches
           where tournament_id=:'_t'::uuid and group_label='B'), 3,
  'group B has 3 group fixtures');
select is((select count(*)::int from public.matches m
           join public.tournament_matches tm on tm.match_id=m.id
           where tm.tournament_id=:'_t'::uuid and m.overs_limit=20
             and m.scorer_id=tests.get_supabase_uid('org@s.dev') and m.status='setup'), 6,
  'each fixture is a setup matches row owned/scored by the organizer with the tournament overs');
select is((select status::text from public.tournaments where id=:'_t'::uuid), 'group_stage',
  'tournament status flips to group_stage');
select throws_ok($$ select public.generate_group_fixtures(
  (select id from public.tournaments where name='Cup')) $$,
  'P0001', null, 'generating fixtures twice is rejected');

select * from finish();
rollback;
