begin;
select plan(2);
select has_function('public','broadcast_dm_message','dm broadcast fn');
select has_trigger('public','dm_messages','dm_messages_broadcast','dm broadcast trigger');
select * from finish();
rollback;
