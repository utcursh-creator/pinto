begin;
select plan(1);
-- Proves the helpers loaded (via seed.sql) and a fake authenticated user can be created.
select isnt(tests.create_supabase_user('smoke@test.dev'), null, 'can create a supabase test user');
select * from finish();
rollback;
