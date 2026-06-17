begin;
select plan(9);

-- Task 1: enum + column
select has_type('public', 'lf_flair', 'lf_flair enum type exists');
select has_column('public', 'looking_for_posts', 'flair', 'looking_for_posts has a flair column');
select col_not_null('public', 'looking_for_posts', 'flair', 'looking_for_posts.flair is NOT NULL');
select results_eq(
  $$ select unnest(enum_range(null::public.lf_flair))::text order by 1 $$,
  $$ values ('corporate_match'), ('loser_pays'), ('practice_match') $$,
  'lf_flair has exactly the three expected labels'
);

-- Task 2: flair threaded through the RPCs
select tests.create_supabase_user('flair@m.dev');
select tests.authenticate_as('flair@m.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('flair@m.dev'), 'Flair Tester');

select public.create_looking_for_post('player_seeking_team', 'loser_pays', 19.07, 72.87, 'need a team') as _p \gset
select is(
  (select flair::text from public.looking_for_posts where id = :'_p'::uuid),
  'loser_pays',
  'create_looking_for_post stores the flair'
);
select is(
  (select flair::text from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_p'::uuid),
  'loser_pays',
  'discover_posts returns the post flair column'
);
select is(
  (select count(*)::int from public.discover_posts(19.07, 72.87, 10000, null, null, null, null, 'loser_pays') d where d.post_id = :'_p'::uuid),
  1,
  'discover_posts returns the post when _flair matches'
);
select is(
  (select count(*)::int from public.discover_posts(19.07, 72.87, 10000, null, null, null, null, 'corporate_match') d where d.post_id = :'_p'::uuid),
  0,
  'discover_posts excludes the post when _flair differs'
);
select is(
  (select count(*)::int from public.discover_posts(19.07, 72.87, 10000, null, null, null, null, null) d where d.post_id = :'_p'::uuid),
  1,
  'discover_posts returns the post when _flair is null (no filter)'
);

select * from finish();
rollback;
