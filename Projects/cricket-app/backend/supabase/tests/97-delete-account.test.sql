begin;
select plan(6);
-- MISS-4: delete_my_account removes a clean account outright; an account with
-- match history is anonymized (scorecards survive under "Deleted user") and its
-- login identity scrubbed.
select tests.create_supabase_user('clean@d.dev');
select tests.create_supabase_user('scorer@d.dev');

-- clean account: full delete cascades profile + posts
select tests.authenticate_as('clean@d.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('clean@d.dev'), 'Clean');
select public.create_looking_for_post('player_seeking_team', 'practice_match', 19.07, 72.87, 'hi');
select public.delete_my_account();
reset role;
select is((select count(*)::int from public.profiles where display_name = 'Clean'),
  0, 'a clean account''s profile is deleted');
select is((select count(*)::int from auth.users where email = 'clean@d.dev'),
  0, 'a clean account''s auth user is deleted');

-- scorer with match history: anonymized, matches survive. Capture the uid
-- BEFORE deletion - anonymization scrubs raw_user_meta_data, which is where the
-- test helper's identifier lives, so lookups by name stop working (by design).
select tests.authenticate_as('scorer@d.dev');
select tests.get_supabase_uid('scorer@d.dev') as _sc \gset
insert into public.profiles(id, display_name) values (:'_sc'::uuid, 'Scorer');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset
select public.delete_my_account();
reset role;
select is(
  (select display_name from public.profiles where id = :'_sc'::uuid),
  'Deleted user', 'a scorer''s profile is anonymized, not deleted');
select is((select count(*)::int from public.matches where id = :'_m'::uuid),
  1, 'their matches survive');
select is(
  (select count(*)::int from auth.users
    where id = :'_sc'::uuid
      and email like 'deleted-%@deleted.invalid'
      and banned_until is not null),
  1, 'the login identity is scrubbed + banned');
select is(
  (select count(*)::int from auth.identities where user_id = :'_sc'::uuid),
  0, 'auth identities are removed');

select * from finish();
rollback;
