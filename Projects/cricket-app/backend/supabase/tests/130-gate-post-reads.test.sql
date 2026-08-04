begin;
select plan(9);
-- Whole-system review #2 (2026-07-28), finding 63.
--
-- post_replies was `using (true)`, so one paginated GET returned every reply
-- body ever written, to any post, anywhere - the free-text field where people
-- type their phone number and which gate of the park they meet at - each joined
-- to its author. post_detail then resolved any post id at all to a title, a
-- place label, a match time and the author's name, because its entire WHERE
-- clause was `p.id = _post_id`.
--
-- Together that is a permanent global index of who is looking for a game,
-- roughly where, and with whom, harvestable by an account nowhere near any of
-- them - defeating every containment the feed applies.
--
-- The CONTROLS carry the risk here. Over-tightening breaks the product: the
-- discover feed, replying to an ad, and reviewing your own closed post are all
-- ordinary things that must keep working.

select tests.create_supabase_user('author@pg.dev');
select tests.create_supabase_user('replier@pg.dev');
select tests.create_supabase_user('snoop@pg.dev');

select tests.authenticate_as('author@pg.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('author@pg.dev'), 'Author');
select public.create_looking_for_post(
  _mode => 'team_seeking_players', _flair => 'practice_match', _lat => 18.52, _lng => 73.85,
  _description => 'Need 2 players, ring me on 98xxxxxxxx',
  _title => 'Sunday game', _place_label => 'Shivaji Park') as _open \gset
select public.create_looking_for_post(
  _mode => 'team_seeking_players', _flair => 'practice_match', _lat => 18.52, _lng => 73.85,
  _description => 'Old ad, meet behind the north gate',
  _title => 'Last week', _place_label => 'Shivaji Park') as _closed \gset

-- somebody replies to the ad that is about to be closed
select tests.authenticate_as('replier@pg.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('replier@pg.dev'), 'Replier');
insert into public.post_replies(post_id, author_id, body)
values (:'_closed'::uuid, tests.get_supabase_uid('replier@pg.dev'), 'I am in - 98xxxxxxxx');

-- the author closes it (the ad is filled)
select tests.authenticate_as('author@pg.dev');
select public.mark_post_filled(:'_closed'::uuid);

-- ============ THE LEAK ============
select tests.authenticate_as('snoop@pg.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('snoop@pg.dev'), 'Snoop');

-- 1. a stranger must not be able to hoover up reply bodies from a closed ad
select is(
  (select count(*)::int from public.post_replies where post_id = :'_closed'::uuid),
  0, 'a stranger cannot read replies on a closed ad');

-- 2. nor resolve that ad to a name, a place and a time
select is(
  (public.post_detail(:'_closed'::uuid) ->> 'title'),
  null, 'a stranger cannot resolve a closed ad through post_detail');

-- ============ CONTROLS: the product must still work ============

-- 3-4. an OPEN ad is exactly what the feed is for - it must stay readable, or
--      Discover shows nothing and nobody can reply to anything
select is(
  (public.post_detail(:'_open'::uuid) ->> 'title'),
  'Sunday game', 'an open ad is still readable by anyone - that is the feed');
select isnt(
  (public.post_detail(:'_open'::uuid) ->> 'author_name'),
  null, 'and still carries the author name the detail screen shows');

-- 5. a stranger can still reply to a live ad
select lives_ok(
  format($$ insert into public.post_replies(post_id, author_id, body)
            values (%L, %L, 'I can play') $$,
         :'_open', tests.get_supabase_uid('snoop@pg.dev')),
  'a stranger can still reply to a live ad');

-- 6. and read the replies on it, which is how a thread works
select is(
  (select count(*)::int from public.post_replies where post_id = :'_open'::uuid),
  1, 'and read that live ad''s thread');

-- 7-8. the AUTHOR keeps full access to their own closed ad
select tests.authenticate_as('author@pg.dev');
select is(
  (public.post_detail(:'_closed'::uuid) ->> 'title'),
  'Last week', 'the author can still review their own closed ad');
select is(
  (select count(*)::int from public.post_replies where post_id = :'_closed'::uuid),
  1, 'and still read the replies people sent them');

-- 9. so does somebody already in the conversation - closing an ad must not
--    erase a thread from the person who answered it
select tests.authenticate_as('replier@pg.dev');
select is(
  (select count(*)::int from public.post_replies where post_id = :'_closed'::uuid),
  1, 'a person who replied keeps the thread after the ad closes');

select * from finish();
rollback;
