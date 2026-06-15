begin;
select plan(7);

-- Three real users
select tests.create_supabase_user('owner@test.dev');
select tests.create_supabase_user('mate@test.dev');
select tests.create_supabase_user('guest@test.dev');
select tests.authenticate_as('owner@test.dev');
insert into public.profiles (id, display_name, city) values (tests.get_supabase_uid('owner@test.dev'), 'Owner', 'Pune');
select tests.authenticate_as('mate@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('mate@test.dev'), 'Mate');
select tests.authenticate_as('guest@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('guest@test.dev'), 'GuestUser');

-- Owner creates team, adds a guest, and a link invite
select tests.authenticate_as('owner@test.dev');
select public.create_team('Pune Panthers', 'Pune') as _t \gset
select public.add_guest_member(:'_t'::uuid, 'Walk-in Guest') as _guest_m \gset
insert into public.team_invites (team_id, invite_token, created_by)
values (:'_t'::uuid, 'tok_join_me', tests.get_supabase_uid('owner@test.dev'));

select is((select count(*)::int from public.team_members where team_id = :'_t'::uuid), 2, 'team has captain + guest');

-- Mate joins via invite
select tests.authenticate_as('mate@test.dev');
select isnt(public.accept_invite('tok_join_me'), null, 'mate accepts invite');
select is((select role::text from public.team_members
           where team_id = :'_t'::uuid and profile_id = tests.get_supabase_uid('mate@test.dev')),
          'player', 'mate joined as player');

-- Guest user claims the walk-in guest; owner approves.
-- (Inside lives_ok's $$..$$ identify the guest row by name via subquery; :vars are not interpolated there.)
select tests.authenticate_as('guest@test.dev');
select isnt(public.request_guest_claim(:'_guest_m'::uuid), null, 'guest user requests claim');
select tests.authenticate_as('owner@test.dev');
select lives_ok(
  $$ select public.approve_guest_claim(
       (select tm.id from public.team_members tm join public.teams t on t.id = tm.team_id
        where t.name = 'Pune Panthers' and tm.guest_name = 'Walk-in Guest'),
       tests.get_supabase_uid('guest@test.dev')) $$,
  'owner approves claim');

-- Final roster: 3 real members, no guests left
select is((select count(*)::int from public.team_members where team_id = :'_t'::uuid and profile_id is not null), 3, 'three real members');
select is((select count(*)::int from public.team_members where team_id = :'_t'::uuid and guest_name is not null), 0, 'no unclaimed guests remain');

select * from finish();
rollback;
