begin;
select plan(3);
select tests.create_supabase_user('a@m.dev'); select tests.create_supabase_user('b@m.dev');
select tests.authenticate_as('a@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
select public.create_looking_for_post('team_seeking_players', 'practice_match', 19.07, 72.87, 'need 2', null, null, null, null, null, 2) as _p \gset
select tests.authenticate_as('b@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('b@m.dev'),'B');
select has_table('public','post_replies','post_replies table');
-- b uses the known post id (as the app does from the feed) - after SEC-2 a
-- non-author can no longer read the raw looking_for_posts row to discover it.
select lives_ok(format($$ insert into public.post_replies(post_id, author_id, body) values (%L, %L, 'I can play') $$, :'_p'::uuid, tests.get_supabase_uid('b@m.dev')), 'authed user can reply');
select throws_ok(format($$ insert into public.post_replies(post_id, author_id, body) values (%L, %L, 'spoof') $$, :'_p'::uuid, tests.get_supabase_uid('a@m.dev')), '42501', null, 'cannot reply as another user');
select * from finish();
rollback;
