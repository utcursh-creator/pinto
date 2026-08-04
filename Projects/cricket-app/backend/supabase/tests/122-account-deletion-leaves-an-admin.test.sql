begin;
select plan(4);
-- HIGH (whole-system review #2): delete_my_account nulls out the departing
-- user's memberships WITHOUT the last-captain guard that leave_team enforces.
-- Delete the account of a team's only captain and the team is frozen forever:
-- nobody can add a player, start a match, accept an invite or promote anyone,
-- because every one of those paths requires is_team_admin and no admin exists.
select tests.create_supabase_user('solo@k.dev');
select tests.create_supabase_user('mate@k.dev');
select tests.authenticate_as('solo@k.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('solo@k.dev'), 'Solo');
select public.create_team('Frozen XI', 'Pune') as _t \gset
select public.create_team_invite(:'_t'::uuid) as _tok \gset
select tests.authenticate_as('mate@k.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('mate@k.dev'), 'Mate');
select public.accept_invite(:'_tok'::text) as _mm \gset

-- the sole captain deletes their account
select tests.authenticate_as('solo@k.dev');
select lives_ok($$ select public.delete_my_account() $$,
  'deleting the account still succeeds - the person must always be able to leave');

-- 2. THE BUG: somebody must still be able to administer the team
select tests.authenticate_as('mate@k.dev');
select ok(public.is_team_admin(:'_t'::uuid),
  'the team still has an admin after its only captain deletes their account');

-- 3. and that admin can actually do the thing an admin exists to do
select lives_ok(
  format($$ select public.add_guest_member(%L, 'Someone New') $$, :'_t'),
  'the surviving member can still add a player');

-- 4. and the LAST person on a team may still delete their account - there is
-- nobody left to promote, and refusing would trap them in the app forever.
select tests.create_supabase_user('lone@k.dev');
select tests.authenticate_as('lone@k.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('lone@k.dev'), 'Lone');
select public.create_team('Only Me XI', 'Pune') as _o \gset
select lives_ok($$ select public.delete_my_account() $$,
  'the last member of a team can still delete their account');

select * from finish();
rollback;
