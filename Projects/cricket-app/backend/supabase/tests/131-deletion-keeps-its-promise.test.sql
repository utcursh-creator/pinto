begin;
select plan(7);
-- Whole-system review #2 (2026-07-28), findings 35 and 52: account deletion
-- does not do what the app tells the user it does.
--
-- The confirmation dialog says, in these words:
--
--   "This permanently removes your profile, posts and messages."
--
-- delete_my_account removes the posts. It never touched dm_messages, so every
-- private message the person ever sent stayed in the database verbatim - and it
-- never touched post_replies, which is the other free-text field where people
-- put their phone number. Their uploaded avatar and post photos also stayed in
-- public buckets, still served at their original URLs, forever.
--
-- Someone asking to be forgotten is the one case where a half-kept promise is
-- worse than no promise, because they acted on it and stopped worrying.
--
-- The line this fix must not cross: deleting THEIR words, not everyone's. The
-- other side of a conversation belongs to the other person and must survive.

select tests.create_supabase_user('leaver@dl.dev');
select tests.create_supabase_user('friend@dl.dev');
select tests.create_supabase_user('other@dl.dev');

select tests.authenticate_as('friend@dl.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('friend@dl.dev'), 'Friend');
select tests.authenticate_as('other@dl.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('other@dl.dev'), 'Other');

select tests.authenticate_as('leaver@dl.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('leaver@dl.dev'), 'Leaver');

select tests.get_supabase_uid('leaver@dl.dev') as _me    \gset
select tests.get_supabase_uid('friend@dl.dev') as _fr    \gset
select tests.get_supabase_uid('other@dl.dev')  as _ot    \gset

-- a private conversation, with words from BOTH sides
select public.get_or_create_dm_thread(:'_fr'::uuid) as _th \gset
insert into public.dm_messages(thread_id, sender_id, body)
values (:'_th'::uuid, :'_me'::uuid, 'my number is 98xxxxxxxx');
set local role postgres;
insert into public.dm_messages(thread_id, sender_id, body)
values (:'_th'::uuid, :'_fr'::uuid, 'great, see you sunday');

-- a reply they left on somebody else's ad
insert into public.looking_for_posts(id, author_id, mode, flair, title, description, geog, place_label)
values (gen_random_uuid(), :'_ot'::uuid, 'team_seeking_players', 'practice_match',
        'Need players', 'come along',
        extensions.st_setsrid(extensions.st_makepoint(73.85, 18.52), 4326)::extensions.geography,
        'Pune')
returning id as _post \gset
insert into public.post_replies(post_id, author_id, body)
values (:'_post'::uuid, :'_me'::uuid, 'I can play - ring 98xxxxxxxx');

set local role authenticated;

-- ---- they ask to be forgotten ----
select public.delete_my_account();

set local role postgres;

-- 1-2. their words are gone, from both places they can be written
select is(
  (select count(*)::int from public.dm_messages where sender_id = :'_me'::uuid),
  0, 'every private message they sent is gone - the dialog promised "messages"');
select is(
  (select count(*)::int from public.post_replies where author_id = :'_me'::uuid),
  0, 'and every reply they left on other people''s ads');

-- 3. THE LINE: the other person's messages are the other person's
select is(
  (select count(*)::int from public.dm_messages where sender_id = :'_fr'::uuid),
  1, 'but the friend''s side of the conversation survives - those words are '
     'not the leaver''s to delete');

-- The PHOTOS are deliberately NOT asserted here. Supabase rejects any direct
-- DELETE on storage.objects at the database level (verified: the statement
-- aborts the transaction), because removing the row would orphan the file
-- rather than delete it. That half of the promise is kept by the client through
-- the Storage API and is pinned by app/test/account_deletion_removes_photos_test.dart.

-- 6. CONTROL: the promise is about THEIR data. Somebody else's reply on the
--    same post must not be collateral.
select tests.authenticate_as('other@dl.dev');
insert into public.post_replies(post_id, author_id, body)
values (:'_post'::uuid, :'_ot'::uuid, 'me too');
set local role postgres;
select is(
  (select count(*)::int from public.post_replies where author_id = :'_ot'::uuid),
  1, 'a third party''s reply on the same ad is untouched');

-- 7-9. and the parts deletion deliberately KEEPS still work, so the scorecard
--      of a match they played does not lose a player (pgTAP 121's contract)
select is(
  (select display_name from public.profiles where id = :'_me'::uuid),
  'Deleted user', 'the profile row survives, renamed, so history still renders');
select is(
  (select count(*)::int from auth.sessions where user_id = :'_me'::uuid),
  0, 'their sessions are revoked');
select is(
  (select count(*)::int from public.looking_for_posts where author_id = :'_me'::uuid),
  0, 'their own posts are gone, as they always were');

select * from finish();
rollback;
