begin;
select plan(7);
-- MISS-6/TEAM-2/3: one shared invite link admits the whole squad (multi-use),
-- expires, honors max_uses, and can be revoked.
select tests.create_supabase_user('cap@i.dev');
select tests.create_supabase_user('j1@i.dev');
select tests.create_supabase_user('j2@i.dev');
select tests.create_supabase_user('j3@i.dev');

select tests.authenticate_as('cap@i.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@i.dev'), 'Cap');
select public.create_team('Strikers', 'C') as _t \gset
select public.create_team_invite(:'_t'::uuid) as _tok \gset

-- TEAM-2: TWO different users redeem the SAME token
select tests.authenticate_as('j1@i.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('j1@i.dev'), 'J1');
select isnt(public.accept_invite(:'_tok'), null, 'the first tapper joins');
select tests.authenticate_as('j2@i.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('j2@i.dev'), 'J2');
select isnt(public.accept_invite(:'_tok'), null,
  'the SECOND tapper joins on the same token (multi-use)');
select tests.authenticate_as('cap@i.dev');
select is((select uses from public.team_invites where invite_token = :'_tok'),
  2, 'each new join burns one use');

-- re-accepting when already a member is a no-op that burns no use
select tests.authenticate_as('j1@i.dev');
select isnt(public.accept_invite(:'_tok'), null, 're-accept returns the membership');
select tests.authenticate_as('cap@i.dev');
select is((select uses from public.team_invites where invite_token = :'_tok'),
  2, 're-accepting does not burn a use');

-- TEAM-3: expiry is enforced
update public.team_invites set expires_at = now() - interval '1 minute'
  where invite_token = :'_tok';
select tests.authenticate_as('j3@i.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('j3@i.dev'), 'J3');
select throws_ok(
  format($$ select public.accept_invite(%L) $$, :'_tok'),
  'P0001', 'invite expired', 'an expired invite is refused');

-- max_uses is enforced
select tests.authenticate_as('cap@i.dev');
select public.create_team_invite(:'_t'::uuid) as _tok2 \gset
update public.team_invites set max_uses = 0 where invite_token = :'_tok2';
select tests.authenticate_as('j3@i.dev');
select throws_ok(
  format($$ select public.accept_invite(%L) $$, :'_tok2'),
  'P0001', 'invite fully used', 'a maxed-out invite is refused');

select * from finish();
rollback;
