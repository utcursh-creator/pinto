begin;
select plan(4);
select has_table('public','dm_threads','dm_threads');
select has_table('public','dm_participants','dm_participants');
select has_table('public','dm_messages','dm_messages');
select has_function('public','is_thread_participant',array['uuid'],'is_thread_participant(uuid)');
select * from finish();
rollback;
