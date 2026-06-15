begin;
select plan(5);
select has_table('public', 'teams', 'teams table exists');
select col_is_pk('public', 'teams', 'id', 'id is PK');
select col_type_is('public', 'teams', 'name', 'text', 'name is text');
select col_not_null('public', 'teams', 'name', 'name is required');
select fk_ok('public', 'teams', 'created_by', 'public', 'profiles', 'id');
select * from finish();
rollback;
