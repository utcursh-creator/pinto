begin;
select plan(5);
-- HIGH (whole-system review #2): "Block user" only closed DMs. The blocked
-- person kept replying on the victim's looking-for posts, which is the most
-- public surface in the app - so the one action a harassed user takes did
-- almost nothing, while appearing to work.
select tests.create_supabase_user('victim@b.dev');
select tests.create_supabase_user('troll@b.dev');
select tests.create_supabase_user('normal@b.dev');

select tests.authenticate_as('victim@b.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('victim@b.dev'), 'Victim');
select public.create_looking_for_post(
  'player_seeking_team'::public.lf_mode, 'practice_match'::public.lf_flair,
  19.0760, 72.8777, 'need a game') as _post \gset

select tests.authenticate_as('troll@b.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('troll@b.dev'), 'Troll');
select tests.authenticate_as('normal@b.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('normal@b.dev'), 'Normal');

-- 1. before any block, anyone may reply
select tests.authenticate_as('troll@b.dev');
select lives_ok(
  format($$ insert into public.post_replies(post_id, author_id, body)
            values (%L, %L, 'hello') $$, :'_post', tests.get_supabase_uid('troll@b.dev')),
  'anyone can reply to an open post');

-- the victim blocks the troll
select tests.authenticate_as('victim@b.dev');
insert into public.blocked_users(blocker_id, blocked_id)
  values (tests.get_supabase_uid('victim@b.dev'), tests.get_supabase_uid('troll@b.dev'));

-- 2. THE BUG: the blocked person must not be able to reply any more
select tests.authenticate_as('troll@b.dev');
select throws_ok(
  format($$ insert into public.post_replies(post_id, author_id, body)
            values (%L, %L, 'still here') $$, :'_post', tests.get_supabase_uid('troll@b.dev')),
  '42501', null, 'a blocked person cannot reply to the blocker''s post');

-- 3. blocking is symmetric - the victim does not want to be pulled into the
-- troll's threads either
select tests.authenticate_as('troll@b.dev');
select public.create_looking_for_post(
  'player_seeking_team'::public.lf_mode, 'practice_match'::public.lf_flair,
  19.0760, 72.8777, 'troll post') as _tpost \gset
select tests.authenticate_as('victim@b.dev');
select throws_ok(
  format($$ insert into public.post_replies(post_id, author_id, body)
            values (%L, %L, 'hi') $$, :'_tpost', tests.get_supabase_uid('victim@b.dev')),
  '42501', null, 'and the blocker is not dragged into the blocked person''s posts');

-- 4. everyone else is unaffected
select tests.authenticate_as('normal@b.dev');
select lives_ok(
  format($$ insert into public.post_replies(post_id, author_id, body)
            values (%L, %L, 'count me in') $$, :'_post', tests.get_supabase_uid('normal@b.dev')),
  'an unrelated player can still reply');

-- 5. and the author can always reply on their own post
select tests.authenticate_as('victim@b.dev');
select lives_ok(
  format($$ insert into public.post_replies(post_id, author_id, body)
            values (%L, %L, 'thanks') $$, :'_post', tests.get_supabase_uid('victim@b.dev')),
  'the author can reply on their own post');

select * from finish();
rollback;
