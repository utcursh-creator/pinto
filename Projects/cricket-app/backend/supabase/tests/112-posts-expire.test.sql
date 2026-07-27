begin;
select plan(6);
-- MEDIUM (penetration review 2026-07-07): looking-for posts never expired
-- because no client path ever wrote expires_at, and the feed had no match-date
-- floor - so Discover silted up with dead ads that outranked fresh ones purely
-- by being nearer.

select tests.create_supabase_user('exp@e.dev');
select tests.authenticate_as('exp@e.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('exp@e.dev'), 'Exp');

-- 1. an UNDATED post gets a 14-day expiry, not null
select public.create_looking_for_post(
  'players_seeking_team'::public.lf_mode, 'practice_match'::public.lf_flair,
  19.0760, 72.8777, 'undated') as _undated \gset
select ok(
  (select expires_at from public.looking_for_posts where id = :'_undated'::uuid)
    between now() + interval '13 days' and now() + interval '15 days',
  'an undated post expires in about 14 days');

-- 2. a DATED post dies the day after the match
select public.create_looking_for_post(
  'players_seeking_team'::public.lf_mode, 'practice_match'::public.lf_flair,
  19.0760, 72.8777, 'dated',
  _match_at := now() + interval '2 days') as _dated \gset
select ok(
  (select expires_at from public.looking_for_posts where id = :'_dated'::uuid)
    between now() + interval '2 days' and now() + interval '4 days',
  'a dated post expires just after the match, not in 14 days');

-- 3. an explicit expiry still wins
select public.create_looking_for_post(
  'players_seeking_team'::public.lf_mode, 'practice_match'::public.lf_flair,
  19.0760, 72.8777, 'explicit',
  _expires_at := now() + interval '1 hour') as _explicit \gset
select ok(
  (select expires_at from public.looking_for_posts where id = :'_explicit'::uuid)
    < now() + interval '2 hours',
  'an explicit expiry is respected');

-- 4. a match that already happened is NOT offered, however near it is
select public.create_looking_for_post(
  'players_seeking_team'::public.lf_mode, 'practice_match'::public.lf_flair,
  19.0760, 72.8777, 'yesterday',
  _match_at := now() - interval '1 day') as _past \gset
select is(
  (select count(*)::int from public.discover_posts(19.0760, 72.8777)
    where post_id = :'_past'::uuid),
  0, 'a match that already happened is not in the feed');

-- 5. an EXPIRED post is not offered either
reset role;  -- fixture: force an expiry into the past
update public.looking_for_posts set expires_at = now() - interval '1 minute'
  where id = :'_undated'::uuid;
select tests.authenticate_as('exp@e.dev');
select is(
  (select count(*)::int from public.discover_posts(19.0760, 72.8777)
    where post_id = :'_undated'::uuid),
  0, 'an expired post is not in the feed');

-- 6. the live, dated post IS still offered
select is(
  (select count(*)::int from public.discover_posts(19.0760, 72.8777)
    where post_id = :'_dated'::uuid),
  1, 'an upcoming match is still offered');

select * from finish();
rollback;
