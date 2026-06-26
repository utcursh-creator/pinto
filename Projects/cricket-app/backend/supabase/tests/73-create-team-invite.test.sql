-- create_team_invite: an admin mints a shareable token; anyone signed-in can
-- redeem it via accept_invite to join the team. Pairs with the existing
-- accept_invite RPC to make the registered-player invite flow reachable.
begin;
select plan(5);
select tests.create_supabase_user('admin@s.dev');
select tests.create_supabase_user('joiner@s.dev');
select tests.authenticate_as('admin@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('admin@s.dev'),'Admin');
select public.create_team('Royals','Jaipur') as _t \gset

-- A) an admin mints an invite token
select public.create_team_invite(:'_t'::uuid) as _tok \gset
select isnt(:'_tok', null::text, 'create_team_invite returns a token');
select is((select status::text from public.team_invites where invite_token = :'_tok'), 'pending',
  'the invite is pending');

-- B) a signed-in user redeems it and joins the team
select tests.authenticate_as('joiner@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('joiner@s.dev'),'Joiner');
select isnt(public.accept_invite(:'_tok'), null::uuid, 'accept_invite returns a membership id');
select is(
  (select count(*)::int from public.team_members
   where team_id = :'_t'::uuid and profile_id = tests.get_supabase_uid('joiner@s.dev')),
  1, 'the joiner is now a member');

-- C) a non-admin cannot mint invites
select throws_ok($$ select public.create_team_invite(
  (select id from public.teams where name='Royals')) $$,
  'P0001', null, 'a non-admin cannot create an invite');

select * from finish();
rollback;
