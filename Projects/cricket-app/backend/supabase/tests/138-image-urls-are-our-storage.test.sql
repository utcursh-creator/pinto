begin;
select plan(8);
-- Whole-system review #2 (2026-07-28), finding 62: photo_url, image_urls and
-- logo_url were unvalidated client-supplied strings - a tracking beacon.
--
-- An attacker points their own photo_url at a host they control, joins a public
-- squad, and every screen that draws them makes an unauthenticated GET to that
-- host: the VIEWER's IP, User-Agent and a timestamped record of who looked.
-- public_profile_minimal returns photo_url to anon and the public routes bypass
-- the auth gate, so it fires for logged-out visitors too.
--
-- The host is no longer stored. A value is normalised on write to the host-free
-- `/storage/v1/object/public/<bucket>/<name>` and the client resolves it
-- against its own configured origin, so the attacker cannot choose a host that
-- is not written down. Shape-checking alone would have been theatre - anyone
-- can serve that path - so the object must also EXIST in our storage.

select tests.create_supabase_user('att@img.dev');
select tests.authenticate_as('att@img.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('att@img.dev'), 'Att');
select tests.get_supabase_uid('att@img.dev') as _me \gset

-- a real upload, exactly as the client makes one
set local role postgres;
insert into storage.objects(bucket_id, name, owner)
values ('avatars', :'_me'::text || '/1.jpg', :'_me'::uuid);
set local role authenticated;

-- 1. the ordinary path still works, and is stored host-free
update public.profiles
   set photo_url = 'http://127.0.0.1:54321/storage/v1/object/public/avatars/'
                   || :'_me'::text || '/1.jpg'
 where id = :'_me'::uuid;
select is(
  (select photo_url from public.profiles where id = :'_me'::uuid),
  '/storage/v1/object/public/avatars/' || :'_me'::text || '/1.jpg',
  'a genuine upload is kept, with the host stripped off');

-- 2. THE BEACON: an attacker-controlled host cannot be stored
update public.profiles
   set photo_url = 'https://attacker.example/p.png?v=' || :'_me'::text
 where id = :'_me'::uuid;
select is(
  (select photo_url from public.profiles where id = :'_me'::uuid),
  null, 'a foreign URL is refused - it cannot become an avatar that fires at '
        'every viewer who loads a roster');

-- 3. and neither can one that MIMICS our path on a foreign host, because the
--    host is not stored at all
update public.profiles
   set photo_url = 'https://attacker.example/storage/v1/object/public/avatars/'
                   || :'_me'::text || '/1.jpg'
 where id = :'_me'::uuid;
select is(
  (select photo_url from public.profiles where id = :'_me'::uuid),
  '/storage/v1/object/public/avatars/' || :'_me'::text || '/1.jpg',
  'mimicking our path on another host gains nothing - the host is stripped, so '
  'the client resolves it against ITS OWN origin');

-- 4. a path that resolves to no real object is refused
update public.profiles
   set photo_url = '/storage/v1/object/public/avatars/' || :'_me'::text || '/nope.jpg'
 where id = :'_me'::uuid;
select is(
  (select photo_url from public.profiles where id = :'_me'::uuid),
  null, 'shape alone is not enough - the object has to exist in our storage');

-- 5-6. teams.logo_url takes the same treatment
select public.create_team('Beacon CC', 'Pune') as _t \gset
update public.teams
   set logo_url = 'https://attacker.example/logo.png' where id = :'_t'::uuid;
select is(
  (select logo_url from public.teams where id = :'_t'::uuid),
  null, 'a team logo cannot point at a foreign host either');
set local role postgres;
insert into storage.objects(bucket_id, name, owner)
values ('avatars', :'_me'::text || '/logo.png', :'_me'::uuid);
set local role authenticated;
update public.teams
   set logo_url = 'http://127.0.0.1:54321/storage/v1/object/public/avatars/'
                  || :'_me'::text || '/logo.png' where id = :'_t'::uuid;
select is(
  (select logo_url from public.teams where id = :'_t'::uuid),
  '/storage/v1/object/public/avatars/' || :'_me'::text || '/logo.png',
  'and a real one still works');

-- 7-8. post images: bad entries are dropped, good ones kept in order
set local role postgres;
insert into storage.objects(bucket_id, name, owner)
values ('post-images', :'_me'::text || '/a.jpg', :'_me'::uuid),
       ('post-images', :'_me'::text || '/b.jpg', :'_me'::uuid);
set local role authenticated;
select public.create_looking_for_post(
  _mode => 'team_seeking_players', _flair => 'practice_match',
  _lat => 18.52, _lng => 73.85, _description => 'x', _title => 'Beacon post',
  _place_label => 'Pune',
  _image_urls => array[
    'http://127.0.0.1:54321/storage/v1/object/public/post-images/' || :'_me'::text || '/a.jpg',
    'https://attacker.example/track.gif',
    'http://127.0.0.1:54321/storage/v1/object/public/post-images/' || :'_me'::text || '/b.jpg'
  ]) as _post \gset
set local role postgres;
select is(
  (select array_length(image_urls, 1) from public.looking_for_posts where id = :'_post'::uuid),
  2, 'the attacker image is dropped from the post and the two real ones kept');
select is(
  (select image_urls[1] from public.looking_for_posts where id = :'_post'::uuid),
  '/storage/v1/object/public/post-images/' || :'_me'::text || '/a.jpg',
  'and the survivors keep their order, host-free');

select * from finish();
rollback;
