begin;
select plan(7);

-- bucket + columns + storage RLS
select is((select count(*)::int from storage.buckets where id = 'post-images'), 1, 'post-images bucket exists');
select has_column('public', 'looking_for_posts', 'image_urls', 'looking_for_posts.image_urls exists');
select has_column('public', 'looking_for_posts', 'link_url', 'looking_for_posts.link_url exists');
select is(
  (select count(*)::int from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and policyname = 'post_images_insert_own'),
  1, 'storage upload policy for post-images exists');

-- RPC threads image_urls + link_url through
select tests.create_supabase_user('att@m.dev');
select tests.authenticate_as('att@m.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('att@m.dev'), 'Att');
select public.create_looking_for_post(
  _mode := 'player_seeking_team', _flair := 'loser_pays', _lat := 19.07, _lng := 72.87,
  _image_urls := array['https://x/a.jpg','https://x/b.jpg'],
  _link_url := 'https://maps.example/ground'
) as _p \gset
select is(
  (select array_length(image_urls, 1) from public.looking_for_posts where id = :'_p'::uuid),
  2, 'create_looking_for_post stores two image urls');
select is(
  (select link_url from public.looking_for_posts where id = :'_p'::uuid),
  'https://maps.example/ground', 'create_looking_for_post stores the link');
select is(
  (select array_length(image_urls, 1) from public.discover_posts(19.07, 72.87, 10000) d where d.post_id = :'_p'::uuid),
  2, 'discover_posts returns the image urls');

select * from finish();
rollback;
