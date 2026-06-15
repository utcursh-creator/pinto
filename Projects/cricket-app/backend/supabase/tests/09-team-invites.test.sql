begin;
select plan(5);

select tests.create_supabase_user('cap@test.dev');
select tests.create_supabase_user('joiner@test.dev');
select tests.authenticate_as('cap@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('cap@test.dev'), 'Cap');
select tests.authenticate_as('joiner@test.dev');
insert into public.profiles (id, display_name) values (tests.get_supabase_uid('joiner@test.dev'), 'Joiner');

select tests.authenticate_as('cap@test.dev');
select public.create_team('Titans', 'Delhi') as _t \gset

-- Schema checks
select has_table('public', 'team_invites', 'team_invites table exists');
select col_has_default('public', 'team_invites', 'status', 'status defaults');

-- Cap creates a link invite (admin only) and it starts pending
insert into public.team_invites (team_id, invite_token, created_by)
values (:'_t'::uuid, 'tok_abc123', tests.get_supabase_uid('cap@test.dev'));
select is((select status::text from public.team_invites where invite_token = 'tok_abc123'),
          'pending', 'invite starts pending');

-- Joiner accepts via RPC -> becomes a member, invite accepted
select tests.authenticate_as('joiner@test.dev');
select isnt(public.accept_invite('tok_abc123'), null, 'accept_invite returns a membership id');
select is(
  (select count(*)::int from public.team_members
    where team_id = :'_t'::uuid and profile_id = tests.get_supabase_uid('joiner@test.dev')),
  1, 'joiner is now a member');

select * from finish();
rollback;
