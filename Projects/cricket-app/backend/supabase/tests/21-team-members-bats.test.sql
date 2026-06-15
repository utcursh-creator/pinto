begin;
select plan(2);
select has_column('public','team_members','bats','team_members has bats');
select col_type_is('public','team_members','bats','bats_hand','bats is bats_hand');
select * from finish();
rollback;
