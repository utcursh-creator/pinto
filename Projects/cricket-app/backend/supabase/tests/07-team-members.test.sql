begin;
select plan(6);
select has_table('public', 'team_members', 'team_members table exists');
select col_is_null('public', 'team_members', 'profile_id', 'profile_id is nullable (guests)');
select col_is_null('public', 'team_members', 'guest_name', 'guest_name is nullable (real users)');
select fk_ok('public', 'team_members', 'team_id', 'public', 'teams', 'id');

-- The XOR constraint: exactly one of profile_id / guest_name is set.
select throws_ok(
  $$ insert into public.team_members (team_id, profile_id, guest_name)
     values (gen_random_uuid(), null, null) $$,
  '23514', null, 'rejects a member with neither profile_id nor guest_name');

select has_index('public', 'team_members', 'team_members_unique_profile', 'unique (team_id, profile_id) index exists');

select * from finish();
rollback;
