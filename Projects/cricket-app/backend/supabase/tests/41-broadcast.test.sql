begin;
select plan(2);
select has_function('public','broadcast_delivery_change','broadcast trigger function exists');
select has_trigger('public','deliveries','deliveries_broadcast','broadcast trigger is attached');
select * from finish();
rollback;
