begin;
select plan(3);
select tests.create_supabase_user('a@m.dev');
select tests.authenticate_as('a@m.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('a@m.dev'),'A');
select isnt(public.create_looking_for_post('player_seeking_team', 'corporate_match', 19.07, 72.87, 'need a team Sunday', null, null, null, null, null, null), null, 'create returns id');
select _p.id as _pid from public.looking_for_posts _p limit 1 \gset
select public.cancel_post(:'_pid'::uuid);
select is((select status::text from public.looking_for_posts where id = :'_pid'::uuid), 'cancelled', 'cancel sets status');
select is((select count(*)::int from public.looking_for_posts where author_id = tests.get_supabase_uid('a@m.dev')), 1, 'one post by author');
select * from finish();
rollback;
