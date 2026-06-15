begin;
select plan(1);
select has_function('public','is_match_scorer',array['uuid'],'is_match_scorer(uuid) exists');
select * from finish();
rollback;
