begin;
select plan(1);
select has_extension('postgis', 'postgis is installed');
select * from finish();
rollback;
