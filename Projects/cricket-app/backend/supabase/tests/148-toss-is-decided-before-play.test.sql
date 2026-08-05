begin;
select plan(8);
-- Review #3: re-entering setup on an already-live match rewrites its toss, and
-- then tells the scorer nothing happened.
--
-- The route in is the OTHER finding in the same screen: nothing invalidates
-- myMatchesProvider when a match goes setup -> live, so the scorer's own Matches
-- tile still says "Setup - not started" for a game four overs old, and the only
-- menu item it offers is "Resume setup". Tapping it walks back through the
-- squads screen (which succeeds - every player is still listed, so the
-- "already played" guard never fires) onto a BLANK toss form.
--
-- _start then awaits set_toss FIRST. Each RPC is its own transaction, so the
-- toss write COMMITS; the start_innings that follows violates the
-- one-innings-per-number unique key and throws, and the screen says "Could not
-- start the match" - implying nothing happened. Meanwhile the public,
-- login-free /watch/<id> Info tab now names the wrong toss winner for a match
-- that is being played.
--
-- Verified by hand on the live database before this file existed: set_toss on a
-- live match with 4 runs already scored committed happily.
--
-- The rule: a toss is decided BEFORE play. Once an innings exists, it is part of
-- the record.

select tests.create_supabase_user('cap@toss.dev');
select tests.authenticate_as('cap@toss.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@toss.dev'),'Cap');
select public.create_team('Toss A','Pune') as _a \gset
select public.create_team('Toss B','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'s')  as _s  \gset
select public.add_guest_member(:'_a'::uuid,'ns') as _ns \gset
select public.add_guest_member(:'_b'::uuid,'bw') as _bw \gset
select public.add_guest_member(:'_b'::uuid,'b2') as _b2 \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m \gset

-- 1-2. before play the toss is freely settable, and re-settable: a scorer who
--      taps the wrong team on the setup screen must be able to fix it.
select lives_ok(format($$ select public.set_toss(%L,%L,'bat') $$, :'_m', :'_a'),
  'the toss can be set during setup');
select lives_ok(format($$ select public.set_toss(%L,%L,'bowl') $$, :'_m', :'_b'),
  'and corrected, as long as nobody has bowled a ball');
select is((select toss_winner_id from public.matches where id = :'_m'::uuid),
  :'_b'::uuid, 'the correction stuck');

-- play starts
select public.start_innings(:'_m'::uuid,1,:'_b'::uuid,:'_a'::uuid,:'_bw'::uuid,:'_b2'::uuid) as _i \gset

-- 4. THE BUG: the toss is now part of the record
select throws_ok(
  format($$ select public.set_toss(%L,%L,'bat') $$, :'_m', :'_a'),
  'P0001', 'the toss cannot be changed once play has started',
  'a live match refuses a new toss - the public Info tab would otherwise name '
  'the wrong winner for a game being played');

-- 5. and it really did not move
select is((select toss_winner_id from public.matches where id = :'_m'::uuid),
  :'_b'::uuid, 'the committed toss is untouched');

-- 6. the same after the innings break, which is still mid-match
select public.record_ball(:'_i'::uuid, :'_s'::uuid, 4);
select throws_ok(
  format($$ select public.set_toss(%L,%L,'bowl') $$, :'_m', :'_a'),
  'P0001', 'the toss cannot be changed once play has started',
  'and with runs on the board');

-- 7. CONTROL: a DIFFERENT match, still in setup, is unaffected - the guard is
--    about this match having started, not about the scorer or the clock.
select public.create_match(:'_a'::uuid,:'_b'::uuid,20) as _m2 \gset
select lives_ok(format($$ select public.set_toss(%L,%L,'bat') $$, :'_m2', :'_a'),
  'another match still in setup is untouched by the guard');

-- 8. CONTROL: the finished-match refusal that was already there still fires,
--    with its own message - the new guard must not swallow it.
select public.set_match_result(:'_m2'::uuid, 'abandoned');
select throws_ok(
  format($$ select public.set_toss(%L,%L,'bat') $$, :'_m2', :'_b'),
  'P0001', 'this match already finished',
  'and a finished match still says so in its own words');

select * from finish();
rollback;
