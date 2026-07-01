begin;
select plan(6);
select has_table('public', 'profiles', 'profiles table exists');
select col_is_pk('public', 'profiles', 'id', 'id is PK');
select col_type_is('public', 'profiles', 'id', 'uuid', 'id is uuid');
select col_type_is('public', 'profiles', 'display_name', 'text', 'display_name is text');
select col_not_null('public', 'profiles', 'display_name', 'display_name is required');
select col_type_is('public', 'profiles', 'batting_style', 'batting_style', 'batting_style uses enum');
-- phone moved to the self-only profile_private table (SEC-1); see 80-profile-privacy-handle.
select * from finish();
rollback;
