begin;
select plan(7);
-- Whole-system review #2 (2026-07-28), finding 61: matches.status is stuck at
-- 'innings_break' when a correction reopens the first innings.
--
-- The console writes the break once the fold says the innings ended. The scorer
-- then deletes the wrong final wicket from the Ball log, the fold recomputes to
-- in_progress, the run pad returns and scoring carries on - but nothing writes
-- the status back. mark_innings_break only fires on 'live', and
-- 'innings_break' -> 'live' happens only inside start_innings.
--
-- For the rest of that innings the viewer shows no LIVE badge, the Watch-live
-- list says "innings break" and the Matches tile agrees - while balls are being
-- recorded.

select tests.create_supabase_user('cap@rb.dev');
select tests.authenticate_as('cap@rb.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@rb.dev'),'Cap');
select public.create_team('RB A','Pune') as _a \gset
select public.create_team('RB B','Pune') as _b \gset
select public.add_guest_member(:'_a'::uuid,'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid,'NS') as _ns \gset
select public.add_guest_member(:'_b'::uuid,'BW') as _bw \gset

-- squad_size 2 makes a single wicket all out, so the innings can be ended and
-- reopened with one delivery
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,6,'{"squad_size":2}'::jsonb) as _m \gset
select public.start_innings(:'_m'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_s'::uuid,:'_ns'::uuid) as _i \gset

select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,wicket_type,dismissed_player_id)
 values (:'_i'::uuid,1,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,'bowled',:'_s'::uuid);
update public.matches set status = 'live' where id = :'_m'::uuid;
set local role :_seedrole;

select is(
  (public.compute_innings_state(:'_i'::uuid)->>'innings_status'),
  'completed', 'the innings has ended');
select public.mark_innings_break(:'_m'::uuid);
select is(
  (select status::text from public.matches where id = :'_m'::uuid),
  'innings_break', 'and the match says so');

-- the scorer deletes that wicket from the ball log
select public.delete_ball(
  (select id from public.deliveries where innings_id = :'_i'::uuid and seq = 1));
select is(
  (public.compute_innings_state(:'_i'::uuid)->>'innings_status'),
  'in_progress', 'the innings is open again');

-- 4. THE BUG: the match still claims to be at the interval
select public.resume_from_innings_break(:'_m'::uuid);
select is(
  (select status::text from public.matches where id = :'_m'::uuid),
  'live', 'and the match goes back to live, so viewers stop being told the '
          'game is at the interval while balls are being bowled');

-- 5. CONTROL: it is idempotent - calling it on a live match changes nothing
select public.resume_from_innings_break(:'_m'::uuid);
select is(
  (select status::text from public.matches where id = :'_m'::uuid),
  'live', 'calling it again is harmless');

-- 6. CONTROL: it asks the FOLD, so it cannot drag a genuinely ended innings
--    back to live. A blind `set status = live` would have done exactly that.
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat,wicket_type,dismissed_player_id)
 values (:'_i'::uuid,2,:'_bw'::uuid,:'_s'::uuid,:'_ns'::uuid,0,'bowled',:'_s'::uuid);
set local role :_seedrole;
select public.mark_innings_break(:'_m'::uuid);
select public.resume_from_innings_break(:'_m'::uuid);
select is(
  (select status::text from public.matches where id = :'_m'::uuid),
  'innings_break', 'a genuinely completed innings stays at the break');

-- 7. CONTROL: only the scorer may call it
select tests.create_supabase_user('rando@rb.dev');
select tests.authenticate_as('rando@rb.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rando@rb.dev'),'R');
select throws_ok(
  format($$ select public.resume_from_innings_break(%L) $$, :'_m'),
  'P0001', null, 'a stranger cannot change the match status');

select * from finish();
rollback;
