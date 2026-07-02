begin;
select plan(5);
-- DISC-8: team_invite_preview resolves a token to the team name + redeemability
-- without exposing the invite row; unknown tokens return null; a redeemed token
-- reads as not-redeemable.
select tests.create_supabase_user('adm@s.dev');
select tests.create_supabase_user('joiner@s.dev');

select tests.authenticate_as('adm@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('adm@s.dev'), 'Adm');
select public.create_team('Strikers', 'C') as _t \gset
select public.create_team_invite(:'_t'::uuid) as _tok \gset

-- a different (invited) user can preview the token
select tests.authenticate_as('joiner@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('joiner@s.dev'), 'Joiner');
select is(public.team_invite_preview(:'_tok')->>'team_name', 'Strikers',
  'preview resolves the inviting team name');
select is((public.team_invite_preview(:'_tok')->>'redeemable')::boolean, true,
  'a pending invite previews as redeemable');

-- an unknown token previews as null (clear invalid state)
select is(public.team_invite_preview('nope'), null,
  'an unknown token previews as null');

-- MISS-6: invites are multi-use - one redemption leaves it redeemable...
select public.accept_invite(:'_tok');
select is((public.team_invite_preview(:'_tok')->>'redeemable')::boolean, true,
  'a redeemed multi-use invite stays redeemable');
-- ...but an admin revoke kills it
select tests.authenticate_as('adm@s.dev');
update public.team_invites set status = 'expired' where invite_token = :'_tok';
select is((public.team_invite_preview(:'_tok')->>'redeemable')::boolean, false,
  'a revoked invite previews as not redeemable');

select * from finish();
rollback;
