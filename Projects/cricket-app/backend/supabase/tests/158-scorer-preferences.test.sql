begin;
select plan(7);
-- Journey map C1 (ceiling) + the user's instruction that this be "fundamentally
-- built and integrated and wired properly into the entire app".
--
-- The app had NO preferences mechanism at all. The wagon wheel was mandatory,
-- which is why a dot ball opened a modal on the most common event in cricket.
-- Nobody ships placement capture that way: in CricHQ it is a SETTING you turn
-- on, and plotting DOT BALLS is a further option inside it.
--
-- Account-level, not device-level: a scorer who reinstalls, or scores from a
-- second phone, keeps his choice. profiles is already own-row for writes, so
-- this needs one column and one merge RPC - no new table, no new RLS surface.
--
-- MERGE, not replace: the client sends only the key it changed. A set that
-- silently wiped the other flags would be the same class of bug as the
-- authoritative squad save that dropped players nobody mentioned.

select tests.create_supabase_user('p1@pref.dev');
select tests.create_supabase_user('p2@pref.dev');
select tests.authenticate_as('p1@pref.dev');
insert into public.profiles(id, display_name)
  values (tests.get_supabase_uid('p1@pref.dev'), 'P1');

-- 1. a fresh profile has no preferences, which the client reads as "all off"
select is(
  (select preferences from public.profiles where id = tests.get_supabase_uid('p1@pref.dev')),
  '{}'::jsonb,
  'a new profile starts with no preferences - every scorer aid is OFF until '
  'asked for, which is the whole point');

-- 2. setting one returns the merged object
select is(
  public.set_preferences('{"wagon_capture": true}'::jsonb),
  '{"wagon_capture": true}'::jsonb,
  'set_preferences returns what the profile now holds');

-- 3. THE MERGE. Setting a second key must not wipe the first.
select is(
  public.set_preferences('{"wagon_dot_balls": true}'::jsonb),
  '{"wagon_capture": true, "wagon_dot_balls": true}'::jsonb,
  'a second setting MERGES - the client sends only what changed, and a replace '
  'would silently turn off a preference the scorer never touched');

-- 4. and it can turn something back off
select is(
  public.set_preferences('{"wagon_capture": false}'::jsonb)->>'wagon_capture',
  'false',
  'and a preference can be turned back off');

-- 5. it lands on the ROW, not just in the return value
select is(
  (select preferences->>'wagon_dot_balls' from public.profiles
    where id = tests.get_supabase_uid('p1@pref.dev')),
  'true', 'the profile row really holds it');

-- 6. AUTHORIZATION: it writes MY row, whoever else exists
select tests.authenticate_as('p2@pref.dev');
insert into public.profiles(id, display_name)
  values (tests.get_supabase_uid('p2@pref.dev'), 'P2');
select public.set_preferences('{"wagon_capture": true}'::jsonb);
select is(
  (select preferences->>'wagon_capture' from public.profiles
    where id = tests.get_supabase_uid('p1@pref.dev')),
  'false',
  'P2 setting his own preference does not touch P1 - the RPC writes the '
  'CALLER''s row and takes no user id from the client');

-- 7. anonymous callers have no profile to write to
select tests.clear_authentication();
select throws_ok(
  $$ select public.set_preferences('{"wagon_capture": true}'::jsonb) $$,
  '42501', null, 'an anonymous visitor cannot set preferences');

select * from finish();
rollback;
