begin;
select plan(6);

select tests.create_supabase_user('cap@test.dev');
select tests.create_supabase_user('claimer@test.dev');
select tests.authenticate_as('cap@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('cap@test.dev'), 'Cap');
select tests.authenticate_as('claimer@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('claimer@test.dev'), 'Claimer');

-- Cap makes a team and a guest
select tests.authenticate_as('cap@test.dev');
select public.create_team('Royals', 'Jaipur') as _t \gset
select public.add_guest_member(:'_t'::uuid, 'Mystery Guest') as _m \gset

-- Claimer requests the guest membership (:'_m' is interpolated here because this is bare SQL,
-- not a dollar-quoted string; psql does NOT interpolate :vars inside $$..$$).
select tests.authenticate_as('claimer@test.dev');
select isnt(public.request_guest_claim(:'_m'::uuid), null, 'claimer can request a guest claim');

-- A non-admin cannot approve. Inside throws_ok's $$..$$ we identify the membership with a
-- subquery (the non-captain, role='player' row of team Royals) since :vars are not interpolated there.
select throws_ok(
  $$ select public.approve_guest_claim(
       (select tm.id from public.team_members tm join public.teams t on t.id = tm.team_id
        where t.name = 'Royals' and tm.role = 'player'),
       tests.get_supabase_uid('claimer@test.dev')) $$,
  'P0001', 'not authorized', 'non-admin cannot approve a claim');

-- Cap approves
select tests.authenticate_as('cap@test.dev');
select lives_ok(
  $$ select public.approve_guest_claim(
       (select tm.id from public.team_members tm join public.teams t on t.id = tm.team_id
        where t.name = 'Royals' and tm.role = 'player'),
       tests.get_supabase_uid('claimer@test.dev')) $$,
  'admin can approve the claim');

-- Membership now belongs to claimer; guest_name cleared
select is((select profile_id from public.team_members where id = :'_m'::uuid),
          tests.get_supabase_uid('claimer@test.dev'), 'membership now owned by claimer');
select is((select guest_name from public.team_members where id = :'_m'::uuid),
          null, 'guest_name cleared after claim');

-- Guard: re-approving an already-claimed membership is rejected (P0001). Still authed as cap (admin).
select throws_ok(
  $$ select public.approve_guest_claim(
       (select tm.id from public.team_members tm join public.teams t on t.id = tm.team_id
        where t.name = 'Royals' and tm.role = 'player'),
       tests.get_supabase_uid('claimer@test.dev')) $$,
  'P0001', null, 're-approving a claimed membership is rejected');

select * from finish();
rollback;
