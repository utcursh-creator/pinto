begin;
select plan(6);
-- Whole-system review #2 (2026-07-28), finding 58: discover_posts returns every
-- open post inside the radius, with no LIMIT and no pagination.
--
-- The radius is clamped (2 km to 50 km) but that is not a bound on rows: 50 km
-- around a dense city is thousands of live ads, all serialised, sent and parsed
-- on a phone, on every feed open and every pull-to-refresh. The client-side caps
-- added earlier in this review bounded the other list queries; this one returns
-- a set, so a builder .limit() never applied to it.
--
-- The controls matter as much as the cap: the feed must still return the
-- NEAREST posts, in the order it always did, or bounding it quietly turns
-- "closest games near you" into "an arbitrary 100".

select tests.create_supabase_user('feed@dl.dev');
select tests.authenticate_as('feed@dl.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('feed@dl.dev'), 'Feeder');

-- 250 open ads, all within a few km of the probe, so every one is a candidate
set local role postgres;
-- geog_coarse is NOT generated and has no trigger: create_looking_for_post
-- sets it through _snap_geog, and discover_posts filters on it. A fixture that
-- writes only `geog` leaves it null and the feed returns nothing - which looked
-- exactly like the LIMIT failing.
insert into public.looking_for_posts(
  id, author_id, mode, flair, title, description, geog, geog_coarse,
  place_label, status)
select gen_random_uuid(), tests.get_supabase_uid('feed@dl.dev'),
       'team_seeking_players', 'practice_match',
       'Ad ' || g, 'come along',
       extensions.st_setsrid(
         extensions.st_makepoint(73.85 + (g::numeric / 100000), 18.52), 4326)::extensions.geography,
       public._snap_geog(18.52, 73.85 + (g::numeric / 100000)),
       'Pune', 'open'
from generate_series(1, 250) g;
set local role authenticated;

-- 1. the default page is bounded
select is(
  (select count(*)::int from public.discover_posts(18.52, 73.85, 50000)),
  100, 'the feed returns a bounded page, not every ad in a 50 km radius');

-- 2. a caller may ask for fewer
select is(
  (select count(*)::int from public.discover_posts(
     18.52, 73.85, 50000, null, null, null, null, null, 20)),
  20, 'a caller can ask for a smaller page');

-- 3. and cannot ask for the whole table back - the clamp mirrors the radius
select is(
  (select count(*)::int from public.discover_posts(
     18.52, 73.85, 50000, null, null, null, null, null, 100000)),
  200, 'an absurd page size is clamped, so the bound cannot be argued away');

-- 4. nor for zero or a negative page, which would render an empty feed
select is(
  (select count(*)::int from public.discover_posts(
     18.52, 73.85, 50000, null, null, null, null, null, 0)),
  1, 'a zero or negative page size floors at 1 rather than emptying the feed');

-- 5-6. CONTROL: it is still the NEAREST ads, still ordered. Bounding a feed
--      without keeping its ordering turns "games near you" into "an arbitrary
--      hundred", which is a worse bug than the one being fixed.
select ok(
  (select approx_m from public.discover_posts(18.52, 73.85, 50000) limit 1)
  <= (select approx_m from public.discover_posts(18.52, 73.85, 50000) offset 99 limit 1),
  'the page is still nearest-first');
select is(
  (select count(*)::int from public.discover_posts(18.52, 73.85, 2000)),
  100, 'a tighter radius still fills the page from what is actually nearby');

select * from finish();
rollback;
