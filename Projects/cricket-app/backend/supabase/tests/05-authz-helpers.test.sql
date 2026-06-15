begin;
select plan(2);
select has_function('public', 'is_team_member', array['uuid'], 'is_team_member(uuid) exists');
select has_function('public', 'is_team_admin',  array['uuid'], 'is_team_admin(uuid) exists');
select * from finish();
rollback;
