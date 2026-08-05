begin;
select plan(9);
-- Whole-system review #2 (2026-07-28), finding 43: an expired post still reads
-- as 'open' to its author, with no expiry shown and no way to renew.
--
-- discover_posts filters `expires_at > now()` and `match_at >= now() - 6 hours`,
-- so on the Sunday after a Saturday game the ad is invisible to everyone else.
-- My posts shows a status chip reading 'open' plus Mark filled / Cancel, and
-- nothing in the app has ever read or written expires_at. The author is told
-- their ad is live, sees no replies, and can only guess that it died.
--
-- renew_post is the missing verb. It cannot resurrect a cancelled or filled
-- post - those are decisions, not accidents - and a post whose match date has
-- passed must be given a new one, because pushing expires_at alone would leave
-- it filtered out by the match-date floor and the author back where they were.

select tests.create_supabase_user('me@rp.dev');
select tests.create_supabase_user('other@rp.dev');
select tests.authenticate_as('other@rp.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('other@rp.dev'),'Other');
select tests.authenticate_as('me@rp.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('me@rp.dev'),'Me');

-- an undated ad that has run out
select public.create_looking_for_post(
  'team_seeking_players'::public.lf_mode, 'practice_match'::public.lf_flair,
  18.52, 73.85, 'Need 2 players') as _p \gset
select current_role as _seedrole \gset
set local role postgres;
update public.looking_for_posts set expires_at = now() - interval '1 day'
 where id = :'_p'::uuid;
set local role :_seedrole;

select is(
  (select count(*)::int from public.discover_posts(18.52, 73.85, 25000)),
  0, 'the expired ad is invisible to the feed - which is correct, and is '
     'exactly what the author is never told');

-- 2-3. renewing puts it back
select public.renew_post(:'_p'::uuid);
select ok(
  (select expires_at from public.looking_for_posts where id = :'_p'::uuid) > now(),
  'renewing pushes the expiry out');
select is(
  (select count(*)::int from public.discover_posts(18.52, 73.85, 25000)),
  1, 'and the ad is back in the feed');

-- 4-5. a DATED post that has been played needs a new date, not just more time
select public.create_looking_for_post(
  'team_seeking_players'::public.lf_mode, 'practice_match'::public.lf_flair,
  18.52, 73.85, 'Sat 3pm', null, null,
  (now() - interval '3 days')) as _d \gset
select throws_ok(
  format($$ select public.renew_post(%L) $$, :'_d'),
  'P0001', 'give this post a new date',
  'a post whose match has already been played cannot be renewed without a new '
  'date - the feed floors on match_at, so more expiry time alone would leave '
  'it invisible and the author none the wiser');
select public.renew_post(:'_d'::uuid, now() + interval '5 days');
select is(
  (select count(*)::int from public.discover_posts(18.52, 73.85, 25000)),
  2, 'with a new date it is back too');

-- 6. the expiry follows the new date, so it dies the day after that game
select ok(
  (select expires_at from public.looking_for_posts where id = :'_d'::uuid)
    between now() + interval '5 days' and now() + interval '7 days',
  'and its expiry is tied to the new match date, not another fortnight');

-- 7-8. CONTROLS: a decision is not an accident
select public.cancel_post(:'_p'::uuid);
select throws_ok(
  format($$ select public.renew_post(%L) $$, :'_p'),
  'P0001', 'only an open post can be renewed',
  'a cancelled post stays cancelled - renew is for ads that ran out, not an '
  'undo for ads the author withdrew');

select public.create_looking_for_post(
  'team_seeking_players'::public.lf_mode, 'practice_match'::public.lf_flair,
  18.52, 73.85, 'Filled one') as _f \gset
select public.mark_post_filled(:'_f'::uuid);
select throws_ok(
  format($$ select public.renew_post(%L) $$, :'_f'),
  'P0001', 'only an open post can be renewed',
  'and a filled one stays filled');

-- 9. CONTROL: only the author
select tests.authenticate_as('other@rp.dev');
select throws_ok(
  format($$ select public.renew_post(%L) $$, :'_d'),
  'P0001', 'not your post',
  'a stranger cannot keep somebody else''s ad alive');

select * from finish();
rollback;
