begin;
select plan(8);
-- MISS-2: the notification triggers write the in-app inbox - reply / dm (deduped
-- while unread) / invite-accepted / match-live - and the recipient reads only
-- their own rows.
select tests.create_supabase_user('org@n.dev');
select tests.create_supabase_user('rep@n.dev');

select tests.authenticate_as('org@n.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('org@n.dev'), 'Org');
select tests.authenticate_as('rep@n.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('rep@n.dev'), 'Rep');

-- a reply to org's post notifies org
select tests.authenticate_as('org@n.dev');
select public.create_looking_for_post(
  'team_seeking_opponent', 'practice_match', 19.07, 72.87, 'game?') as _p \gset
select tests.authenticate_as('rep@n.dev');
insert into public.post_replies(post_id, author_id, body)
  values (:'_p'::uuid, tests.get_supabase_uid('rep@n.dev'), 'we are in');
select tests.authenticate_as('org@n.dev');
select is(
  (select count(*)::int from public.notifications where type = 'post_reply'),
  1, 'the post author is notified of a reply');
select ok(
  (select body from public.notifications where type = 'post_reply') like 'Rep %',
  'the reply notification names the replier');

-- org replying to their own post does NOT notify
insert into public.post_replies(post_id, author_id, body)
  values (:'_p'::uuid, tests.get_supabase_uid('org@n.dev'), 'bump');
select is(
  (select count(*)::int from public.notifications where type = 'post_reply'),
  1, 'self-replies never notify');

-- a DM notifies the other side once while unread (burst-deduped)
select public.get_or_create_dm_thread(tests.get_supabase_uid('rep@n.dev')) as _th \gset
insert into public.dm_messages(thread_id, sender_id, body)
  values (:'_th'::uuid, tests.get_supabase_uid('org@n.dev'), 'hi'),
         (:'_th'::uuid, tests.get_supabase_uid('org@n.dev'), 'you there?');
select tests.authenticate_as('rep@n.dev');
select is(
  (select count(*)::int from public.notifications where type = 'dm'),
  1, 'a message burst produces ONE unread dm notification');

-- rep cannot see org's notifications (RLS)
select is(
  (select count(*)::int from public.notifications where type = 'post_reply'),
  0, 'a user only sees their own notifications');

-- an accepted team invite notifies the inviter
select tests.authenticate_as('org@n.dev');
select public.create_team('Strikers', 'C') as _t \gset
select public.create_team_invite(:'_t'::uuid) as _tok \gset
select tests.authenticate_as('rep@n.dev');
select public.accept_invite(:'_tok');
select tests.authenticate_as('org@n.dev');
select is(
  (select count(*)::int from public.notifications where type = 'invite_accepted'),
  1, 'the inviter is notified when their invite is accepted');

-- a match going live notifies registered squad members (except the scorer)
select public.create_team('Rivals', 'C') as _t2 \gset
select public.add_guest_member(:'_t2'::uuid, 'g1') as _g1 \gset
select public.add_guest_member(:'_t2'::uuid, 'g2') as _g2 \gset
select public.create_match(:'_t'::uuid, :'_t2'::uuid, 20) as _m \gset
-- squad: org (scorer) + rep (registered) for Strikers
select public.add_squad_member(:'_m'::uuid, :'_t'::uuid,
  (select id from public.team_members where team_id = :'_t'::uuid
     and profile_id = tests.get_supabase_uid('org@n.dev')));
select public.add_squad_member(:'_m'::uuid, :'_t'::uuid,
  (select id from public.team_members where team_id = :'_t'::uuid
     and profile_id = tests.get_supabase_uid('rep@n.dev')));
select public.add_squad_member(:'_m'::uuid, :'_t2'::uuid, :'_g1'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_t2'::uuid, :'_g2'::uuid);
select public.start_innings(:'_m'::uuid, 1, :'_t2'::uuid, :'_t'::uuid,
  :'_g1'::uuid, :'_g2'::uuid);
select tests.authenticate_as('rep@n.dev');
select is(
  (select count(*)::int from public.notifications where type = 'match_live'),
  1, 'a registered squad member is told the match went live');
select tests.authenticate_as('org@n.dev');
select is(
  (select count(*)::int from public.notifications where type = 'match_live'),
  0, 'the scorer who started it is not notified');

select * from finish();
rollback;
