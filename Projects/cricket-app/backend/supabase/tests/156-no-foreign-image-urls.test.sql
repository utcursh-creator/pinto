begin;
select plan(4);
-- Code review (2026-08-05): 20260804240000 normalised image URLs on WRITE only.
-- Rows written before it kept whatever they had, and the client's
-- resolveStorageUrl passes any absolute URL through unchanged
-- (`if (!stored.startsWith('/')) return stored;`), so a pre-existing external
-- URL still renders and every viewer - including logged-out visitors on the
-- public /watch and /player pages - beacons their IP and User-Agent to that
-- host on page load.
--
-- 20260805230000 backfills. This pins BOTH halves: the backfill expression
-- actually cleans legacy rows, and no row in the database holds a foreign URL
-- now (a drift guard, so a future writer that bypasses the trigger is caught).

select tests.create_supabase_user('img@t.dev');
select tests.authenticate_as('img@t.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('img@t.dev'), 'Img');

select current_role as _r \gset
set local role postgres;
-- LEGACY SHAPE: written before the trigger existed, so the trigger is disabled
-- to reproduce it honestly rather than pretending the trigger let it through.
alter table public.profiles disable trigger profiles_normalise_photo;
update public.profiles set photo_url = 'https://tracker.example.com/pixel.png'
 where id = tests.get_supabase_uid('img@t.dev');
alter table public.profiles enable trigger profiles_normalise_photo;

select is(
  (select photo_url from public.profiles where id = tests.get_supabase_uid('img@t.dev')),
  'https://tracker.example.com/pixel.png',
  'sanity: the legacy row really does hold a foreign URL');

-- 2. the backfill expression cleans it
update public.profiles
   set photo_url = public.normalised_storage_path(photo_url)
 where photo_url is not null
   and public.normalised_storage_path(photo_url) is distinct from photo_url;

select is(
  (select photo_url from public.profiles where id = tests.get_supabase_uid('img@t.dev')),
  null,
  'the backfill nulls a URL that names no object in our storage - a broken '
  'avatar is strictly better than one that reports every viewer to a stranger');
set local role :_r;

-- 3-4. DRIFT GUARD: nothing anywhere holds a foreign URL
select is(
  (select count(*)::int from public.profiles
    where photo_url is not null and photo_url not like '/%'), 0,
  'no profile photo_url is an absolute URL');
select is(
  (select count(*)::int from public.teams
    where logo_url is not null and logo_url not like '/%'), 0,
  'no team logo_url is an absolute URL');

select * from finish();
rollback;
