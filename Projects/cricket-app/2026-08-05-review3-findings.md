---
type: review
date: 2026-08-05
project: cricket-app
status: unworked
---

# Whole-system review #3

Run as a 13-agent workflow (`wf_9b84f4f2-5c0`): six independent lenses - cricket
correctness, permissions/exposure, realtime+lifecycle+caching, user journeys,
schema/migrations/data integrity, and TEST INTEGRITY - each piped into its own
skeptic instructed to KILL the findings and to default to refuted when unsure.
2.0M subagent tokens, 646 tool calls, ~24 minutes.

## Read this before working the list

**The skeptics refuted NOTHING.** 23 findings in, 23 out. In both previous
reviews roughly 60% died at that step, so treat `refuted=0` as a fact about the
skeptics, not a compliment to the finders. Every finding below is therefore
UNVERIFIED unless this file says otherwise. Re-verify each one against the code
and the live database before touching anything - that rule is what caught the
error in the header of the next section.

(Mechanical note for whoever re-runs the workflow: the script joined verdicts to
findings by exact title string and the skeptics rewrote the titles, so the join
matched nothing and every finding came back labelled "no verdict returned".
Join on index, or make the skeptic echo the title verbatim.)

## Verified by hand, 2026-08-05

1. **edit_ball accepts dismissals impossible under the Laws - CONFIRMED, and it
   means I refuted review-#2 finding 28 wrongly.** I recorded a legal dot ball
   through record_ball, then called
   `edit_ball(_extra_no_ball_penalty => 1, _wicket_type => 'bowled', ...)`.
   Accepted. The fold then reports `wickets=1, runs=1, legal_balls=0` - a batter
   bowled off a no-ball, in the public scorecard and in player_career_stats. My
   refutation said "record_ball ALREADY validates both guards correctly", which
   is true and beside the point: the finding was about the CORRECTION path,
   which I never opened. Two lenses caught this independently.
2. **discover_posts is executable by PUBLIC - CONFIRMED.** `proacl` is null, so
   there is no ACL at all and `anon` can call it. The LIMIT migration
   (20260804190000) dropped and recreated the function and never re-granted.
3. **matches INSERT - CONFIRMED, WITH THE SCENARIO CORRECTED.** Two teams the
   attacker has nothing to do with is REFUSED by RLS, so "anyone, against a
   stranger's team" is wrong. What IS accepted: an admin of ONE team inserting a
   pre-`complete` match against any other team with an invented result, which
   bypasses the scoring engine and set_match_result's guards and publishes a
   fabricated result naming a team that never agreed to play. Still serious;
   just not the finding as written.

## Also found, by hand, while the review ran

**looking_for_posts grants authenticated UPDATE on every column**, so
`renew_post`, `cancel_post`, `mark_post_filled` and `_snap_geog` are all
optional: an author can PATCH `expires_at` (an ad that never dies), `status` (un-
cancel), or `geog`/`geog_coarse` (put the ad anywhere on earth, defeating the
~550m coarsening). Same shape as the grant findings below. Details in
scratchpad/prefinding-posts-update-grant.md, which also records three things
checked and deliberately NOT changed (team_members DELETE is safe - the FKs are
ON DELETE NO ACTION; no definer function lacks a search_path; no leftover
overloads; and the five remaining bare auth.uid() policies all act on one row).

## FIXED SO FAR

* the two Laws findings (edit_ball / insert_ball accepting impossible
  dismissals) - commit 3c7a112, pgTAP 146
* the four TEST-INTEGRITY findings - commit below. All four confirmed by
  mutation before touching anything, and one turned out WORSE than reported:
  the ErrorRetry allowlist excused a deletion on any screen without a
  behavioural test, so removing the retry from My teams left the suite green.
* the GUEST-REMOVAL HIGH (the "This is me" button shadowing the admin menu) -
  commit below. The last HIGH in the file.
* the two TOSS findings (a live match's toss rewritable + nothing invalidating
  myMatchesProvider on setup -> live) - commit below, pgTAP 148. They are one
  bug in two layers: the stale tile is what leads the scorer back into setup.
* the BADGE HIGH (finding 3) - commit below, pgTAP 149 + JOURNEY N. This also
  closes review-#2's finding 40, which was deferred with the note "fixing it
  properly needs a per-user realtime topic, which is a backend design change".
  That is what this is: ONE private topic per user, `user:<uid>`, fed by both
  the notifications trigger (the bell) and the dm_messages trigger (the mail,
  because notify_dm_message deliberately writes no second notification while an
  unread one exists, so the burst's 2nd and 3rd message would be missed). The
  client half is UserRealtime, watched by the app shell, plus a resume refresh
  on Discover - the socket cannot help a phone that slept through the
  conversation.
* the ALL-OUT ASTERISK (finding 17) - commit below, pgTAP 150. The card read
  striker_id as "at the crease"; on the last wicket of an innings there is no
  incoming batter, so the fold leaves the DISMISSED batter there. Not-out now
  means "at the crease AND not in fall_of_wickets", which is data the viewer
  already held. pgTAP 150 pins the two fold contracts that rule now depends on
  (striker_id IS the out batter after the last wicket; a retired_not_out gets
  NO fall_of_wickets entry) - neither was pinned by anything before.
* FOUND WHILE FIXING IT, not in any finding: four pgTAP files used
  `(select id from public.X limit 1)` to name the object under test. The device
  journeys leave real tournaments, threads and join requests in the local DB,
  and test 90 then picked a JOURNEY's tournament, tripped the organizer check
  instead of the team-admin guard it is named after, and had been passing on
  the wrong error all along. Fixed in 50, 90, 91, 99 by naming the ids. The
  full suite now passes against a DB full of real journey data, which is a
  stricter gate than the clean-reset run.
* the START-A-MATCH DEAD END (finding 18) - commit below. The team selector's
  error branch was a bare line of text: a FAILED read showed strictly less than
  an EMPTY one, because the "Create a team" escape hatch lives in the data
  branch. It now carries an ErrorRetry. The sweep structurally could not catch
  this - the allowlist is keyed on the FILE (deliberately, finding 19) and the
  file's excuse was written for the opponent picker further down - so the proof
  is behavioural.

## REFUTED

* **finding 16 ("Watch live" load failure is a dead end).** Driven, not argued:
  with riverpod's auto-retry disabled, a fling on the error branch takes the
  provider from 1 read to 2. The RefreshIndicator fires. The finding's argument
  was that `ScrollPhysics.shouldAcceptUserOffset` rejects the drag on one short
  child - true of the DEFAULT physics, but a vertical ListView with no
  controller is `primary`, and ScrollView then supplies
  AlwaysScrollableScrollPhysics, which accepts unconditionally. The allowlist
  reason is correct as written.
  What WAS missing is a test: the excuse rested on a property nothing checked.
  Both branches (error and empty) are now pinned in
  `dead_end_error_branches_test.dart`, so giving that ListView a controller or
  `primary: false` fails the suite instead of silently removing the only
  recovery.

* the CROSSED CORRECTION GAP (finding 15) - commit below, pgTAP 151 + JOURNEY E.
  insert_ball had no _crossed parameter at all, and the ball-log editor had no
  control to send one - so a corrected run-out landed with crossed = NULL, all
  three folds took the coalesce(crossed,false) branch, and the wrong batter
  kept the strike for the rest of the innings. edit_ball already ACCEPTED
  _crossed (review #2 gave it one); nothing was sending it.
  pgTAP 151 asserts LOCKSTEP rather than a hand-derived expectation: the
  corrected innings must land where a LIVE-scored one does. And the device
  journey is not decoration here - the widget spy fakes MatchRepository, which
  sits ABOVE the RPC, so deleting `params['_crossed']` passes all 442 widget
  tests. Only the device run joins the two halves.
* the GUEST TOMBSTONE SPLIT (finding 12) - commit below, pgTAP 152.
  add_guest_member (team page) inserted a second row where add_match_guest
  (match squads) revives the tombstone - two live buttons with the same label
  and opposite IRREVERSIBLE outcomes. It had been given the `left_at is null`
  half of the sibling's fix and never the revive, which turns a hard, visible
  block into a silent split. Fixed by copying the sibling's revive verbatim,
  deliberately: the last three bugs in this family were all one reader
  filtering left_at while the other did not.
  My own test was wrong once here and is worth recording: I asserted that
  add_match_guest should still accept the name after the team page re-added
  him. It should not - once revived he IS an active member, so refusing him as
  a NEW guest is correct and the picker is the right door. The assertion now
  checks what matters, that his ORIGINAL membership id can be picked.
* the DM INBOX SCAN (finding 13) - commit below, pgTAP 153. CONFIRMED by my own
  measurement, not taken on faith: at 39,814 participant rows the lookup was a
  Seq Scan touching 294 buffers and discarding 39,615 rows; with the index it is
  an Index Only Scan touching 5. The ratio is not the point - the SHAPE is. The
  cost scaled with the conversations on the PLATFORM rather than the ones this
  user has, and dm_inbox re-runs on every incoming message in any visible
  thread.
  I also swept the whole class (every column that is a non-first member of a
  composite PK with no standalone index): it found blocked_users.blocked_id and
  tournament_teams.team_id. Both were inspected and NEITHER is filtered alone on
  a hot path - blocked_users names both columns everywhere except a
  once-per-lifetime account deletion, and tournament_teams is always driven by
  tournament_id. No speculative indexes added.
* the RENEW-TO-TODAY TRAP (finding 14) - commit below. The renew flow showed a
  DATE-only picker and rebuilt the instant from the OLD time of day, so
  renewing a 09:00 fixture to "today" at 16:00 produced 09:00 today - past the
  feed's 6-hour floor, still invisible, and now with the Expired chip and the
  Renew button gone because this screen computes "expired" from expires_at
  alone. The author ended up worse off than before tapping it. The flow now
  asks for a time and refuses a past-floor result in the composer's own words.
  Tested in TWO halves on purpose, after the _crossed lesson: a pure rule
  (renewedMatchAt, 6 tests, 3 mutations) and a wiring test that drives the real
  pickers on the real screen (4 tests, all RED against the old date-only flow).
  The rule tests alone could not have noticed the screen not calling it.
* the GRANT CLUSTER - 83a4411, pgTAP 147: matches INSERT,
  team_members INSERT/UPDATE/DELETE, looking_for_posts INSERT/UPDATE/DELETE,
  tournaments INSERT/UPDATE/DELETE (not in any finding - the new drift guard
  caught it), and discover_posts' lost EXECUTE grant.

## The theme

Four of the highest-severity findings are one mistake in four places: **a
table-level grant that makes an RPC's guards decorative** (matches INSERT,
team_members INSERT/UPDATE/DELETE, looking_for_posts UPDATE) or **a grant lost
when a function was recreated** (discover_posts). Review #2 fixed exactly this
for `deliveries` and `match_squad`. The fix is a rule, not four patches: no
client-writable table where an RPC owns the invariants, and every
drop+recreate re-states its grants.

---

## 1. [CRITICAL] team_members INSERT grant lets a team admin attach any real user's profile to their roster without consent, then fabricate a permanent public career record on that person's login-free player page

- **file**: `backend/supabase/migrations/20260615140901_team_members_rls.sql`:9


**Failure scenario**

Mallory creates a team (create_team makes her captain -> is_team_admin true). profiles_select_authenticated is `using (true)`, so she reads Priya Sharma's profile id (or gets it from search_players_and_teams). One PostgREST call:
  POST /rest/v1/team_members  {"team_id":"<Mallory XI>","profile_id":"<Priya>","role":"player"}
team_members_insert_admin only checks is_team_admin(team_id); it never asks whether the named profile agreed. There is no BEFORE INSERT trigger on team_members (team_members_immutable_identity_trg is BEFORE UPDATE only) and no notification fires, so Priya is never told.
Reproduced end-to-end in a rolled-back transaction on the live local DB using only client-reachable RPCs after that insert: create_match -> set_match_squad (it accepts Priya: she IS a member of a team in the match) -> set_toss -> start_innings -> record_ball(wicket 'bowled', dismissed_player_id = Priya) -> set_match_result. player_public_profile(Priya) then returns career.matches = 1 and batting = {"runs":0,"balls":1,"ducks":1,"average":0.00,"strike_rate":0.00}. Read as role anon it is identical - the /player/:id screen is top-level and login-free. Priya opens the app and finds a team she never joined in My teams and a golden duck on her career page. Deleting her membership row fails on match_squad_team_member_id_fkey, and leave_team only sets left_at, which does not remove the record: player_career_stats keys off v_player_key = coalesce(profile_id, id) and ignores left_at.


**Why it is real**

Verified by direct probe as role authenticated with request.jwt.claims set, inside BEGIN/ROLLBACK. The grant is 20260615140901_team_members_rls.sql:2 (`grant select, insert, update, delete on public.team_members to authenticated`) and the policy is lines 9-11 of the same file. This is the identical shape 20260707130100_revoke_direct_writes.sql:6-13 closed for tournament_teams - its comment names it: "an organizer could enrol ANY team - the exact unconsented insert the SEC-8 consent model exists to prevent" - and team_members was never given the same treatment. The four consented membership paths (accept_invite, respond_join_request, approve_guest_claim, add_guest_member) are all SECURITY DEFINER and bypass RLS, and the Flutter app performs zero writes to team_members (identity_repository.dart:30, identity_providers.dart:52, match_providers.dart:40 and :214 are all `.select(...)`), so the INSERT grant is unused by the product.

---

## 2. [CRITICAL] matches INSERT grant lets anyone fabricate a COMPLETE match with an arbitrary result against a stranger's team, in one call, permanently corrupting that team's public W/L record

- **file**: `backend/supabase/migrations/20260728120000_matches_insert_participation.sql`:30


**Failure scenario**

Mallory installs the app and taps Create team -> "Mallory XI" (create_team makes her captain, so is_team_admin is true for her own team). She reads any victim club's id (teams_select_authenticated is `using (true)`; search_opponent_teams also returns them). She then issues ONE PostgREST call:
  POST /rest/v1/matches
  {"owner_id":<me>,"scorer_id":<me>,"team_a_id":"<Mallory XI>","team_b_id":"<Shivaji Park CC>","overs_limit":20,"balls_per_over":6,"status":"complete","result":{"result_type":"win_by_runs","winner_team_id":"<Mallory XI>","margin":250,"note":"Shivaji Park CC forfeited"}}
The policy passes: owner_id = uid, scorer_id = uid, and is_team_admin(team_a_id) is true for her throwaway team. Nothing checks status or result.
Reproduced in a rolled-back transaction on the live local DB: team_career_stats('Shivaji Park CC') went from {"played":0,"won":0,"lost":0} to {"played":1,"won":0,"lost":1}, and `set local role anon; select id, status, result->>'note' from public.matches` returned the row (matches_select_anon allows status='complete'). The victim club's team page renders exactly this via team_career_stats (app/lib/src/features/identity/data/identity_providers.dart:88, rendered at app/lib/src/features/teams/presentation/team_page_screen.dart:693 as "P 1 - W 0, L 1"), to logged-out visitors. The victim has no recourse: delete_match refuses anyone who is not owner_id, and there is no UPDATE grant, so no RPC can undo it.


**Why it is real**

20260707130100_revoke_direct_writes.sql:25-33 revoked UPDATE on matches for precisely this reason - its own comment says a client could "PATCH result/status/potm straight onto the row and fabricate a public record for a team that never played" - but line 30-31 of that same file explicitly kept INSERT, and 20260616200501_matches_rls.sql:1 grants INSERT on every column (verified in information_schema.column_privileges: status, result, potm, toss_winner_id are all in the authenticated INSERT column list). The review-#2 fix (finding 6, this file) added a PARTICIPATION rule to the INSERT policy but no status/result rule, and participation is satisfiable by creating a throwaway team in one prior call. set_match_result - the RPC that owns the result rules (winner must be one of this match's teams, no re-resulting a terminal match) - is bypassed entirely; the row is born complete. The Flutter app never writes matches directly (grep for `.from('matches')` followed by insert/update/upsert in app/lib returns nothing), so the INSERT grant is pure attack surface and can be revoked outright in favour of create_match.

---

## 3. [HIGH] The Discover mail/bell badges and the DM inbox itself are fetched once per app launch and never refreshed — no realtime listener exists outside the Messages screen, and nothing re-reads on resume

- **file**: `app/lib/src/features/discover/presentation/discover_screen.dart`:82


**Failure scenario**

Aisha opens Pitch and lands on Discover (the initial branch of the StatefulShellRoute.indexedStack, so it is mounted for the whole session). `dmInboxProvider` and `notificationsProvider` each fetch once. She browses Discover / Matches / her profile for ten minutes. Rahul sends her three DMs and replies to her looking-for post. The mail badge stays absent and the bell badge stays absent — the whole time. She taps the mail icon: `DmInboxScreen.build` does `ref.watch(dmInboxProvider)`, which is a non-autoDispose `FutureProvider` still holding the ten-minute-old `AsyncData`, so the inbox renders Rahul's row with the OLD preview, the OLD timestamp and NO unread badge. Only a manual pull-to-refresh reveals that anything happened. Same for the bell: the post reply is invisible until she opens Notifications, which she has no badge telling her to do.


**Why it is real**

Proof chain, all read in the current tree: (1) `discover_providers.dart:198` and `:240` declare both as plain `FutureProvider(...)`; `riverpod-3.4.2/lib/src/providers/future_provider.dart:107` shows `super.isAutoDispose = false`, so once resolved the value is held for the process lifetime. (2) `grep -rn '\.channel(' lib` returns only `match_viewer_screen.dart:98` and `dm_realtime.dart` — and `grep -rn 'dmRealtimeProvider' lib` returns only `dm_inbox_screen.dart:50` and `dm_thread_screen.dart:216`. So there is NO realtime subscription of any kind while the user is on Discover, and none at all for the `notifications` table (`notify_dm_message` / `notify_post_reply` triggers write rows nobody listens to). (3) `grep -rn 'WidgetsBindingObserver|didChangeAppLifecycleState' lib` returns only `dm_thread_screen.dart:28` and `match_viewer_screen.dart:48` — neither the inbox nor Discover recovers on app resume; `main.dart`/`app.dart` install no global lifecycle hook. (4) Discover's own pull-to-refresh (`discover_screen.dart:161`) invalidates only `discoverFeedProvider(query)`. (5) `DmInboxScreen` opens its per-thread listeners only in `_syncSubscriptions` (`dm_inbox_screen.dart:47`), i.e. only while that screen is mounted, and it passes no `onSubscribed` callback even though `DmRealtime.listen` offers one (`dm_realtime.dart:42`) — so the inbox recovers neither on resubscribe nor on resume, where the thread screen recovers on both. Ledger findings 15/40/41 cover different things (payload size, one channel per thread, thread-screen resync); none covers the inbox/badge being frozen when the Messages screen is not on top.

---

## 4. [HIGH] Nothing invalidates myMatchesProvider when a match goes setup -> live, so the Matches tab shows a live match as "Setup - not started" and its tile routes back into the squad editor

- **file**: `app/lib/src/features/scoring/presentation/toss_openers_screen.dart`:245


**Failure scenario**

Rohit is on the Matches tab. He taps "Start a match", picks two teams, creates it — `start_match_screen.dart:144` invalidates `myMatchesProvider`, and because `MatchesScreen` is still mounted underneath the pushed page it immediately re-fetches and caches the new row with `status = 'setup'`. He picks squads, does the toss, and taps "Start match": `start_innings` sets `matches.status = 'live'`. He scores four overs, then presses back — every step used `pushReplacement`, so the branch stack is `[/matches, /matches/:id/score]` and back lands him on the Matches list. The tile still reads "4-over match  -  Setup - not started", sits under the "Upcoming" heading rather than "Live", its overflow menu offers "Resume setup" instead of "Continue scoring" and hides "Watch (public)", and tapping the tile pushes `Routes.matchSquads(id)` — the squad editor — for a match that is live with four overs already recorded.


**Why it is real**

`toss_openers_screen.dart:245` invalidates only `matchProvider(widget.matchId)` after `repo.startInnings(...)`. `grep -rn 'myMatchesProvider' lib` shows it is invalidated at exactly four sites — `matches_screen.dart:246` (abandon/delete), `scoring_console_screen.dart:828` (setResult), `transfer_scorer_screen.dart:42`, `start_match_screen.dart:144` (create) — and none of them is the setup->live transition. `myMatchesProvider` is a non-autoDispose `FutureProvider` (`match_providers.dart:238`) kept alive by `MatchesScreen.build`'s `ref.watch` (`matches_screen.dart:20`), and `MatchesScreen` stays mounted under a pushed route in its branch navigator. The rendering consequences are literal reads of `matches_screen.dart:124` (`final started = status != 'setup' && status != null`), `:130-137` (the "Setup - not started" subtitle), `:149-156` (menu items) and `:163-169` (`onTap` -> `Routes.matchSquads(id)`). This is exactly the class of bug `test/stale_cache_test.dart` was written for (finding 34, abandon/delete), but the start-of-play transition was never covered — no test in `app/test` asserts it.

---

## 5. [HIGH] Re-entering setup on an already-live match rewrites its toss (public record) and then reports "Could not start the match"

- **file**: `app/lib/src/features/scoring/presentation/toss_openers_screen.dart`:229


**Failure scenario**

Continuing from the stale tile above: Rohit's own Matches list tells him his live game has not started, and the only menu item is "Resume setup". He taps it. `MatchSquadsScreen` loads and prefills the real XI (`_prefillFrom`), he taps "Next: toss" — `set_match_squad` succeeds because every player is still listed, so the "already played" guard never fires — and he is pushReplaced onto the toss screen. `_tossWinner`, `_striker` and `_nonStriker` all start null, so the screen shows a blank toss form for a match that is 4 overs old. He fills it in (picking the other captain by mistake) and taps "Start match". `_start` awaits `repo.setToss(...)` FIRST: `set_toss` only rejects `status in ('complete','abandoned')`, so on a live match it commits `update public.matches set toss_winner_id = ..., toss_decision = ...`. The next await, `repo.startInnings(..., inningsNumber: 1, ...)`, then violates `innings_match_id_innings_number_key` and throws. The screen shows "Could not start the match." — implying nothing happened — while the public, login-free `/watch/:id` Info tab now reads "Chennai Chargers won and chose to bowl" for a match where the other side actually won the toss and batted.


**Why it is real**

Each RPC is its own transaction, so the `set_toss` write commits before `start_innings` fails; there is no rollback across the two awaits (`toss_openers_screen.dart:229-239`, and `match_repository.dart:73-99` shows they are two separate `_c.rpc` calls). `pg_get_functiondef('public.set_toss(uuid,uuid,toss_decision)')` from the live DB shows the only status guard is `if _st in ('complete','abandoned')` — 'live' and 'innings_break' pass. `pg_get_constraintdef` on `public.innings` confirms `innings_match_id_innings_number_key UNIQUE (match_id, innings_number)`, so the second call is guaranteed to throw for innings 1. The toss is rendered publicly at `match_viewer_screen.dart:1124-1156` (`'$tossWinner won and chose to $decision'`) on the anon-readable `/watch/:matchId` route (`app_router.dart:182-187`). Neither `TossOpenersScreen` nor `MatchSquadsScreen` reads `match['status']` to refuse setup on a started match — `grep -n "status"` on both files returns nothing in their guards.

---

## 6. [HIGH] team_members UPDATE grant bypasses the last-captain guards in set_team_member_role and leave_team - a team admin can demote and tombstone the founding captain and lock them out of their own team

- **file**: `backend/supabase/migrations/20260707120000_team_members_update_lockdown.sql`:26


**Failure scenario**

Ravi founds a club (create_team -> role 'captain') and promotes his friend Arun to 'admin' via the Manage roster sheet. Arun is now is_team_admin, which is all team_members_update_admin requires. Three plain PostgREST PATCHes:
  PATCH /rest/v1/team_members?id=eq.<Ravi's row>  {"role":"player"}
  PATCH /rest/v1/team_members?id=eq.<Ravi's row>  {"left_at":"now()"}
  PATCH /rest/v1/team_members?id=eq.<Arun's row>  {"role":"captain"}
Reproduced in a rolled-back transaction on the live local DB: all three return UPDATE 1, and afterwards is_team_admin(team) and is_team_member(team) are both FALSE for Ravi. He opens the app: the club is gone from My teams (myTeams() filters left_at is null, identity_repository.dart:28-35), he is absent from the roster (teamRosterProvider, identity_providers.dart:56), and every admin action is refused. His only route back is request_to_join, which Arun must approve.
Both guards that exist to stop this were skipped. The same set_team_member_role call raises 'a team needs at least one captain' (verified: the RPC path errors at set_team_member_role line 14 for the identical demotion), and leave_team raises 'hand the captaincy to someone else before leaving'. Nothing on the table enforces either, so an admin can also simply tombstone every captain and leave the club in the captain-less, unrecoverable state review #2 documented as a permanent dead end.


**Why it is real**

The 2026-07-07 fix in this file split the UPDATE policy and added team_members_immutable_identity_trg, but that trigger only guards team_id and profile_id (lines 38-49) - role and left_at are untouched, and the policy's USING/WITH CHECK is just is_team_admin(team_id) on both sides. Lines 59-61 of the same migration state the intent - "The app's only direct UPDATE moves to an admin-gated RPC, so the client never needs table-level UPDATE at all" - yet the grant at 20260615140901_team_members_rls.sql:2 was never revoked, so the RPC became advisory rather than authoritative. Confirmed the app has no remaining direct writes to team_members (the four `.from('team_members')` sites in app/lib are all selects), so `revoke insert, update, delete on public.team_members from authenticated` is a clean fix that also closes the unconsented-membership hole above.

---

## 7. [HIGH] team_members still grants INSERT/UPDATE/DELETE to authenticated — every guard in leave_team, set_team_member_role and accept_invite is bypassable with one PostgREST call

- **file**: `backend/supabase/migrations/20260804150000_scoring_writes_rpc_only.sql`:35


**Failure scenario**

All three legs reproduced against the live DB (each in a rolled-back transaction, authenticating with tests.authenticate_as, i.e. exactly what a PostgREST call does).

(a) PERMANENT TEAM BRICK, reachable by ANY user against their own team. Captain C creates a team (create_team makes them sole captain) and adds a guest. `select public.leave_team(<C's membership>)` correctly raises 'hand the captaincy to someone else before leaving'. Then `delete from public.team_members where id = <C's membership>` → DELETE 1. Result measured immediately after: captains_left = 0, is_team_admin(team) = false for everyone, and `select public.add_guest_member(team,'Another')` now raises 'not authorized'. The team can never again add a player, mint an invite, start a match or promote anyone — from inside the app or out. This is review #2 finding 16 ("sole captain deletion freezes team", ledger: CLOSED), closed in the RPC only.

(b) ADMIN → CAPTAIN TAKEOVER. Team with captain C and a member A whom C promoted to 'admin' via set_team_member_role. As A: `select public.set_team_member_role(<C>, 'player')` raises 'a team needs at least one captain'. Then, as A, three raw statements all succeed: `update team_members set role='player' where id=<C>` (UPDATE 1), `update team_members set left_at=now() where id=<C>` (UPDATE 1), `update team_members set role='captain' where id=<A>` (UPDATE 1). Final state read back: A = captain/active, C = player/tombstoned. C is off the roster (every roster reader filters left_at is null) and no longer captain of their own club. The immutable-identity trigger does not fire — team_id and profile_id are untouched.

(c) NON-CONSENSUAL ROSTER ADD. As a captain: `insert into team_members(team_id, profile_id, role) values (<my team>, <a stranger's uid>, 'player')` succeeds, and is_team_member(<my team>) then returns true for the stranger. There is no invite, no join request, no consent — the whole point of team_invites/accept_invite and request_to_join/respond_join_request.


**Why it is real**

information_schema.role_table_grants and has_table_privilege both confirm authenticated still holds INSERT, UPDATE and DELETE on public.team_members, and pg_policies shows the three surviving permissive policies that let the writes through: team_members_update_admin (USING/WITH CHECK is_team_admin(team_id)), team_members_delete_admin_or_self (is_team_admin(team_id) OR profile_id = auth.uid()), team_members_insert_admin (is_team_admin(team_id)). This is exactly the pattern 20260804150000_scoring_writes_rpc_only.sql was written to sweep — its own comment says "a scorer with any HTTP client could bypass all of it" and "that is not what a table-level grant means" — but the revoke batch at lines 35-38 covers only deliveries, innings, match_squad and matches DELETE. team_members, the table with the most guard-bearing SECURITY DEFINER RPCs (leave_team's last-captain guard and history-preserving tombstone, set_team_member_role's last-captain guard, accept_invite's consent + tombstone revival, delete_my_account's captaincy handover), was missed. 20260707120000_team_members_update_lockdown.sql line 62 states "the client never needs table-level UPDATE at all" and then never issues the revoke. No pgTAP test asserts these privileges (grep for has_table_privilege across all 138 test files returns nothing for team_members). The client already routes every one of these through the RPC (identity_repository.dart removeMember/setMemberRole), so revoking insert, update, delete on public.team_members from authenticated, anon costs nothing and closes all three.

---

## 8. [HIGH] discover_posts lost its authenticated-only EXECUTE grant when the LIMIT fix dropped and recreated it - the whole matchmaking feed is now readable with no account

- **file**: `backend/supabase/migrations/20260804190000_discover_posts_limit.sql`:54


**Failure scenario**

The migration correctly DROPs the 8-arg discover_posts (lines 13-15, to avoid an overload) and CREATEs the 9-arg version - but unlike every one of the seven previous migrations that touched this function, it does not re-apply `revoke all ... from public; grant execute ... to authenticated`. Dropping the function destroyed its ACL, so the new one has proacl = NULL, i.e. the default PUBLIC EXECUTE. It is SECURITY DEFINER, so RLS on looking_for_posts (posts_select_own) does not apply.
Anyone holding the app's publishable anon key - which ships inside the APK/IPA and is public by design - can now POST /rest/v1/rpc/discover_posts with no JWT at all and sweep lat/lng across a city, 200 rows a call, with no account, no rate limit and nothing tying the scrape to an identity.
Reproduced on the live local DB: as `role anon`, discover_posts(19.0176, 72.8562, 25000) returned post_id, author_id, author_name 'Ravi Kumar', title, place_label 'Shivaji Park', approx_m, and the full free-text description "Need 2 players Sat 6.30am, Shivaji Park gate. Ring me on 98201 55555." `select proacl from pg_proc where proname='discover_posts'` is NULL, while every other RPC the app calls carries an explicit `authenticated=X/postgres`.


**Why it is real**

Confirmed by ACL introspection and by executing the function as role anon. Grep of the migrations shows revoke/grant pairs for discover_posts in 20260616203401:23-24, 20260617120500:53-54, 20260617130200:54-55, 20260702170200:36-37, 20260706111200:35-36, 20260707130600:98-99 and 20260707160000:91-92 - the gate was deliberate and re-stated seven times, and this migration is the only definition that omits it. It is also the exact data the review-#2 finding-63 fix (20260804160000_gate_post_reads.sql:1-22) was written to protect: that write-up names the description field as "where people actually type 'I'm in, ring me on 98xxxxxxxx'", gated post_detail and post_replies behind post_is_visible (granted to authenticated only), and left the feed RPC itself open to anon. Cross-checked every other RPC the client calls: discover_posts is the only one with a default ACL.

---

## 9. [HIGH] A team admin can never remove a guest player: the "This is me" claim button shadows the admin menu on every guest row

- **file**: `app/lib/src/features/teams/presentation/team_page_screen.dart`:587


**Failure scenario**

A captain opens their team page and taps "Add guest player" (line 170) and types "Rahil" — a typo, or a one-off ringer who never plays again. To fix it they open the guest's row expecting the same overflow menu every other member has ("Remove from team", line 602). There is no menu. `_MemberTile.build` resolves `trailing` in this order: `if (onClaim != null) { trailing = TextButton('This is me') } else if (adminMenu && onMemberAction != null) { trailing = PopupMenuButton(...) }` (lines 586-604). At the call site, `onClaim` is non-null for ANY signed-in non-anonymous viewer looking at a row with `profile_id == null` (line 153) — which includes the captain — while `adminMenu` is `isAdmin && member['profile_id'] != uid`, also true for a guest row (null != uid). So the claim button wins on every guest row, for every viewer, forever. The captain's only trailing control on a guest is "This is me", which sends a claim request on their own team's guest. The guest stays on the roster permanently and keeps appearing in `teamMembersProvider` (match_providers.dart), i.e. in every future match-squad picker.


**Why it is real**

This is purely a widget-precedence gap, not a backend limitation: `identity_repository.removeMember` -> `leave_team(uuid)` (backend/supabase/migrations/20260707180000_leave_team.sql) explicitly handles guest rows — its `coalesce(is_team_admin(_row.team_id) or _row.profile_id = _uid, false)` guard was written specifically because "a GUEST row has profile_id null", and it deletes outright when the member has no history. The 'remove' item in the menu is also deliberately unconditional while the three role items are gated by `if (!isGuest ...)` (lines 596-602), proving removal was intended to work for guests. `grep -rn "removeMember"` shows only two call sites, both in this file, so there is no other path. The widget test test/team_management_test.dart seeds a roster with two registered members and no guest row, so the collision is untested; test/dead_end_controls_test.dart covers finding 71 (roster refresh after claim approval) but not this.

---

## 10. [HIGH] edit_ball and insert_ball accept dismissals impossible under the Laws (bowled off a no-ball, caught off a wide) — the ledger's REFUTED verdict on finding 28 is wrong

- **file**: `backend/supabase/migrations/20260707130300_edit_ball_patch.sql`:54


**Failure scenario**

A scorer records a wicket ball as a legal delivery, then realises the umpire called no-ball. In the Ball log they tap that delivery -> 'Edit this ball' -> Delivery chip = 'No-ball' -> leave Wicket ON with type 'bowled' -> Save. ball_log_screen.dart:531-535 (delivery chips) and :588-591 (wicket-type chips) are completely independent — all eight wicket types are offered whatever the delivery is — and edit_ball performs only correction_wicket_guard (incoming-batter presence) before writing the row. I ran exactly this against the live DB: record a legal dot, then edit_ball(_extra_no_ball_penalty=>1, _wicket_type=>'bowled', ...). Result: compute_innings_state returns runs=1, wickets=1, legal_balls=0, bowling[0].wickets=1, and compute_innings_cards returns the batter with how_out='bowled', dismissed=true. The public scorecard now says a batter was bowled off a no-ball and credits the bowler the wicket. The same holds for insert_ball ('Insert a ball after this'): insert_ball(_extra_wides=>1, _wicket_type=>'caught', _fielder_id=>...) was accepted, producing wickets=2, bowler wickets=2 and compute_innings_cards fielding [{catches:1}] — a catch off a wide. Because compute_innings_cards is the source for player_career_stats, compute_match_potm (frozen into matches.potm by set_match_result) and tournament_leaderboard, the bogus wicket and catch bake into permanent public career records.


**Why it is real**

record_ball enforces both Laws explicitly (record_ball body lines 36-43: 'illegal dismissal on a no-ball/free-hit' restricted to run_out/obstructing/hit_ball_twice; 'illegal dismissal on a wide' restricted to hit_wicket/obstructing/run_out/stumped), and the scoring console mirrors them exactly (scoring_console_screen.dart:1322-1352, _typesFor/_wideWicketTypes/_noBallWicketTypes/_freeHitWicketTypes). Neither guard exists in the current edit_ball (20260707130300_edit_ball_patch.sql, guard call at :54 is correction_wicket_guard only) nor in the current insert_ball (20260804120000_one_broadcast_per_correction.sql:83-118, guard call at :104 is correction_wicket_guard only). pgTAP 125 (125-wicket-off-wide-or-noball.test.sql) asserts the guards only via record_ball — its own header says 'This test pins the other half: that the FOLD counts these deliveries properly' — so nothing covers the correction path. This is review-#2 finding 28, recorded in 2026-08-05-review2-audit.md:112-114 as REFUTED with the rationale 'record_ball ALREADY validates both guards correctly'; that rationale never addresses edit_ball or insert_ball, which is what the finding was about. I proved both paths still accept the illegal rows on the live local DB.

---

## 11. [HIGH] Finding 28 was refuted on the wrong function: edit_ball still writes impossible dismissals, and the fold bakes them into the public scorecard

- **file**: `backend/supabase/migrations/20260707130300_edit_ball_patch.sql`:54


**Failure scenario**

A scorer records a wide, then opens Ball log -> taps that delivery -> 'Edit this ball' -> Wicket ON -> 'bowled' -> picks an incoming batter -> Save (ball_log_screen.dart:588-591 lists all eight wicket types regardless of the Delivery chip; there is no client-side legality check). I ran exactly this against the live DB inside a transaction: after a plain wide, compute_innings_state was runs=1 wickets=0; after one edit_ball(_wicket_type := 'bowled') it became runs=1 wickets=1, and compute_innings_cards credited the bowler {"wides":1,"legal_balls":0,"wickets":1}. record_ball refuses the identical delivery with 'illegal dismissal on a wide'. The batter is now publicly recorded as bowled off a wide, the bowler gets a wicket he cannot have, and that flows into matches.potm and player_career_stats.


**Why it is real**

This is a test-integrity failure, which is why it survived. The only assertions on those two guards are in 38-record-ball.test.sql:27 ('illegal dismissal on a no-ball/free-hit'), and they call record_ball. 125-wicket-off-wide-or-noball.test.sql says in its own header 'record_ball ALREADY validates the Laws correctly ... This test pins the other half: that the FOLD counts these deliveries properly' - i.e. it deliberately does NOT test the guard. The 2026-08-05 ledger then refuted finding 28 with 'record_ball ALREADY validates both guards correctly; pgTAP 125 pins the uncovered half', but finding 28's title and body were about edit_ball and insert_ball, not record_ball. Reading the live definitions: edit_ball's only wicket check is `perform public.correction_wicket_guard(_in, _seq, _eff_wicket, _eff_incoming, false)` (incoming-batter presence only), and insert_ball has no wicket guard at all - its only raise is 'not authorized'. No test in the 138-file suite exercises dismissal legality through either function.

---

## 12. [MEDIUM] add_guest_member creates a duplicate row where add_match_guest revives the tombstone, permanently splitting a returning guest's career and then blocking the path that would have merged it

- **file**: `backend/supabase/migrations/20260707200000_rejoin_after_leaving.sql`:144


**Failure scenario**

Reproduced end to end on the live DB:

1. Captain adds guest 'Ravi Kumar' to Club A and picks him for a match (add_squad_member) — he now has history.
2. End of season, captain removes him: leave_team sees the history and tombstones the row (left_at set, membership id preserved so the old scorecard still names him). Verified: tombstoned = t.
3. Next season Ravi is back. The captain re-adds him from the TEAM PAGE (team_page_screen.dart:486 → identity_repository.addGuest → add_guest_member). The duplicate check only looks at rows with left_at is null, finds none, and INSERTS. Read back: two rows named 'Ravi Kumar' on Club A — the tombstone (has_history = t) and a brand-new active row (has_history = f).
4. Ravi's guest career page is keyed by team_members.id (stats_providers.dart:19), so from the roster he now reads as a player with zero matches; his real record hangs off the tombstone, which teamRosterProvider and teamMembersProvider both filter out — it is unreachable from anywhere in the app.
5. The merge path is now closed too: `select public.add_match_guest(<match>, <Club A>, 'Ravi Kumar')` raises 'a guest with this name is already on the team', because there is finally an ACTIVE row of that name. There is no un-tombstone verb, so this is permanent.

Had the captain used the OTHER 'Add guest' button — the one on the match squads screen (match_squads_screen.dart:276 → add_match_guest) — step 3 would have revived the tombstone and kept his whole career. Two visible buttons for the same act, opposite permanent outcomes.


**Why it is real**

20260804260000_readd_a_departed_guest.sql fixed exactly this shape for add_match_guest, and its comment states the reasoning explicitly: "REVIVE the tombstone rather than making a second row of the same name... a second 'Ravi' on one team would both contradict that and split their record in half", and "splitting one person's career is the more likely harm in a club where the same eleven names recur". add_guest_member was edited in the same family of fixes (20260707200000 added the `and left_at is null` to its duplicate check, line 144) but was never given the matching revive, so the left_at filter alone converts a hard block into a silent split — the third time this codebase has been bitten by one reader filtering left_at and its sibling not. Both call sites are live, user-facing buttons with identical labels.

---

## 13. [MEDIUM] dm_inbox() looks up dm_participants by profile_id, the SECOND column of the composite PK — no usable index, so every inbox load scans the whole table

- **file**: `backend/supabase/migrations/20260804270000_dm_inbox_rpc.sql`:23


**Failure scenario**

Measured on the live DB with 200 decoy profiles → 19,900 dm_threads → 39,800 dm_participants rows, then `explain (analyze, buffers)` on the dm_inbox() body as a user with ZERO conversations:

  CTE mine
    -> Bitmap Heap Scan on dm_participants (rows=0)  Buffers: shared hit=1533
         -> Bitmap Index Scan on dm_participants_pkey
              Index Cond: (profile_id = me.uid)

1,533 buffers (~12 MB) touched to return zero rows. `explain (analyze, buffers) select public.dm_inbox()` on the same data: 824 buffers. Adding `create index on public.dm_participants(profile_id)` and re-running the identical script: 234 buffers — a 3.5x drop, and it stops growing with the platform.

Who hits it: everyone who opens Messages. dm_inbox_screen.dart:70 calls `ref.invalidate(dmInboxProvider)` inside the per-thread realtime listener, so the RPC re-runs on EVERY incoming message in ANY visible thread, plus on every pull-to-refresh and after every markThreadRead (dm_thread_screen.dart:203). On a busy evening a user with ten conversations on screen pays a full dm_participants scan per message that arrives.


**Why it is real**

dm_participants has exactly two indexes: the PK btree(thread_id, profile_id) and nothing else (pg_indexes confirms). dm_inbox()'s `mine` CTE filters on profile_id alone, so the PK is only usable as a full index scan, never as a lookup. This is verbatim the argument migration 20260804140000_scale_indexes.sql makes for match_squad — "the only index mentioning that column is the composite UNIQUE (match_id, team_member_id), where it is the SECOND column - useless for a lookup that does not also know the match" — and that migration added match_squad_member_idx while leaving dm_participants alone. dm_inbox() postdates it (2026-08-04 vs 2026-08-04 12:00) and turned three client round-trips into one server call, which concentrated the whole cost into this one predicate. The `mine` CTE is referenced four times, so PostgreSQL materialises it: one scan per call, unconditionally, before any of the caller's own rows are known.

---

## 14. [MEDIUM] Renewing an expired post to "today" silently re-buries it and removes the Renew button that would let the author notice

- **file**: `app/lib/src/features/discover/presentation/my_posts_screen.dart`:59


**Failure scenario**

A captain posted "Need 2 players, Sat 09:00". The game passed; My posts correctly shows "Expired / Nobody can see this any more" with a Renew button. At 16:00 they tap Renew for a game later today. `_renew` shows a DATE-only picker (lines 51-57, `firstDate: DateTime.now()`, no time picker) and then builds `newDate = DateTime(picked.year, picked.month, picked.day, matchAt.hour, matchAt.minute)` — reusing the OLD 09:00. renew_post's "give this post a new date" guard does not fire, because that guard only triggers when `_match_at is null` (backend/supabase/migrations/20260805130000_renew_post.sql). So match_at becomes today 09:00 (7 hours ago) and expires_at becomes tomorrow 09:00. discover_posts filters `p.match_at >= now() - interval '6 hours'` (20260804190000_discover_posts_limit.sql:39), so the ad is still invisible to everyone. Meanwhile `expired` on this screen is computed purely from expires_at (line 100-101), which is now in the future — so the "Expired" chip, the "Nobody can see this any more" line and the Renew button all disappear and the card reads "open / Expires in 1 day". The author is now worse off than before renewing: the post is still dead and the one control that told them so is gone until tomorrow morning.


**Why it is real**

This is the exact failure renew_post's header comment says it exists to prevent ("Pushing expires_at alone would leave it filtered out by the match-date floor - back in the same silence, which is the bug"); the server guard is bypassed because the client always sends a non-null `_match_at`. The composer already has the matching client-side guard for this rule — `isPastFeedFloor` (new_post_composer.dart:25-26, 89-94) refuses a time past the 6-hour floor and says so — and the renew path has no equivalent, nor any way for the user to express a time of day at all.

---

## 15. [MEDIUM] No correction path can set the run-out `crossed` flag: insert_ball has no _crossed parameter and the ball-log editor never sends one, so a corrected run-out leaves the wrong batter on strike for the rest of the innings

- **file**: `app/lib/src/features/scoring/presentation/ball_log_screen.dart`:341


**Failure scenario**

A ball goes unrecorded (scorer distracted between overs). On it the non-striker was run out and the batters HAD crossed. The scorer opens Ball log -> 'Insert a ball after this' -> Wicket -> Run out -> Who was out: non-striker -> incoming batter -> Insert. There is no 'Batters had crossed' control anywhere in _BallEditorSheet, and MatchRepository.insertBall (match_repository.dart:261-296) has no crossed parameter to send it to — insert_ball's SQL signature does not accept one at all. I verified on the live DB: after inserting such a run-out, `select crossed from deliveries where id = <inserted>` returns NULL, so all three folds take the coalesce(d.crossed,false) branch and skip the crossing swap. The resulting striker for the remainder of the innings is A3 where the correct answer (crossed=true) is A1 — every later run, ball faced, four and six is credited to the wrong batter, and restamp_innings_strike writes the wrong striker_id/non_striker_id onto every subsequent delivery row in the ball log. The same gap applies to an edit: a run-out originally recorded with the crossed switch set the wrong way can never be corrected, because editBall (match_repository.dart:217-259) sends no _crossed and edit_ball is COALESCE-patch shaped so the wrong stored value survives.


**Why it is real**

insert_ball's live signature (verified with pg_get_functiondef) is insert_ball(uuid,bigint,uuid,integer,integer,integer,integer,integer,integer,noball_secondary_kind,wicket_type,uuid,uuid,uuid) — bowler, runs, the five extras, secondary kind, wicket type, dismissed, incoming, fielder. No crossed. The _BallEdit class (ball_log_screen.dart:341-398) has no crossed field and _BallEditorSheet renders no crossed control, while the scoring console does (scoring_console_screen.dart:1517-1520, gated by _needsCrossedRuns). compute_innings_state:125-127, compute_innings_cards:97-99 and restamp_innings_strike:59-61 all apply the crossing swap only when coalesce(d.crossed,false) is true, so the missing flag silently changes the derived strike. This is distinct from the already-closed review-#2 finding that edit_ball DESTROYED an existing crossed value (fixed by making edit_ball a COALESCE patch); the remaining gap is that it can never be SET. Recoverable only by the console's separate Swap strike action, which nothing tells the scorer to use.

---

## 16. [MEDIUM] "Watch live" load failure is a dead end — the ErrorRetry sweep excused it on a pull-to-refresh that provably cannot fire

- **file**: `app/lib/src/features/scoring/presentation/live_matches_screen.dart`:28


**Failure scenario**

A user taps the Watch-live icon on the Matches tab while on poor signal. `liveMatchesProvider` throws, and the error branch renders `ListView(children: [Center(child: Text('Could not load live matches.'))])` — one short child, no button. `liveMatchesProvider` is a plain (non-autoDispose) FutureProvider, so the AsyncError is cached: backing out and re-entering the screen re-watches the same errored element and shows the same line. The user drags down to refresh and nothing happens, because the ListView's content does not overflow the viewport and it uses default physics: `ScrollPhysics.shouldAcceptUserOffset` returns `position.pixels != 0.0 || position.minScrollExtent != position.maxScrollExtent`, which is false here, so the scrollable rejects the drag and the enclosing RefreshIndicator never triggers. The only cure is killing the app.


**Why it is real**

test/error_branches_have_retry_test.dart:49-51 allowlists this exact branch with the reason "live matches: the branch is already inside a RefreshIndicator AND is scrollable, so pull-to-refresh is the retry". The second half of that reason is false — being wrapped in a ListView is not the same as being over-scrollable. The codebase already knows this: dm_thread_screen.dart:426 and tournaments_list_screen.dart:86 both pass `physics: const AlwaysScrollableScrollPhysics()` for precisely this reason, and neither the error branch nor the empty branch here does. Verified against the installed SDK (~/development/flutter/packages/flutter/lib/src/widgets/scroll_physics.dart:218-226 and :956). test/live_matches_test.dart exercises only the populated and empty cases, never the error case.

---

## 17. [MEDIUM] On every all-out innings the public scorecard marks the last batter dismissed as not out

- **file**: `app/lib/src/features/scoring/presentation/match_viewer_screen.dart`:887


**Failure scenario**

A side is bowled out. Anyone opens the login-free /watch/<match id> viewer, Scorecard tab. The batting card puts a ' *' beside every row whose batter_id equals s['striker_id'] or s['non_striker_id'] — but when an innings ends all out, record_ball permits (and requires) a null incoming batter on the final wicket, so compute_innings_state leaves the dismissed batter sitting in _striker/_non_striker. I verified this on the live DB with a 3-player batting squad (all_out = 2): after the second wicket, innings_status='completed', wickets=2, and striker_id = 2ca45653... — the very batter compute_innings_cards reports as dismissed=true, how_out='bowled'. The rendered card therefore shows TWO batters with a not-out asterisk on an innings that lost all its wickets, one of whom the fall-of-wickets line three rows below names as dismissed. The card contradicts itself, and readers of a public scorecard (the login-free share target) are told a batter was not out when he was bowled.


**Why it is real**

match_viewer_screen.dart:887 is `'${b['batter_id'] == strikerId || b['batter_id'] == nonStrikerId ? '  *' : ''}'`, with strikerId/nonStrikerId read at :830-831 straight from compute_innings_state, and the comment at :839-840 confirms the asterisk means 'at the crease'/not out. compute_innings_state:150-153 only substitutes the incoming batter `if d.incoming_batter_id is not null`, and record_ball:45-49 explicitly allows a null incoming batter when wickets_remaining < 2, so on the last wicket of every innings the out batter is never removed from the pair. The correct not-out information does exist — compute_innings_cards emits `dismissed` and `how_out` per batter — but the viewer's scorecard reads compute_innings_state, which carries neither. Proven on the live local DB, not inferred.

---

## 18. [MEDIUM] "Start a match" is permanently dead after one failed team read — no retry, and the allowlist reason describes a different branch

- **file**: `app/lib/src/features/scoring/presentation/start_match_screen.dart`:164


**Failure scenario**

A user opens Matches -> "Start a match" in a car park with one bar. `myTeamsProvider` throws, and the "Your team" section renders `error: (e, _) => Text(humanError(e))` — a bare line of text. There is no dropdown and, crucially, no "Create a team" button either: the AppEmpty escape hatch that handles a user with zero teams lives in the `data:` branch (lines 170-180), so a failed read shows strictly less than an empty read. "Next: squads" stays enabled (line 260-263), and every tap answers "Still needed: your team." — naming a field the screen never rendered a control for. `myTeamsProvider` is a plain FutureProvider (identity_providers.dart:8), so the failure is cached: backing out to Matches and re-entering shows the same thing. The only in-app recovery is to leave the tab entirely, go Profile -> My teams, and tap the ErrorRetry there — which nothing on this screen suggests.


**Why it is real**

test/error_branches_have_retry_test.dart:40-41 allowlists the literal string "error: (e, _) => Text(humanError(e))" with the reason "inline beside the opponent picker in the match wizard". That reason does not describe this branch: the opponent picker's own error branch is a different string (start_match_screen.dart:378, `error: (e, _) => Center(child: Text(humanError(e)))`) and has its own separate allowlist entry at test line 42-43. The guard matched the wrong branch, so the primary team selector of the app's headline flow slipped through the sweep uncaught. The same provider's branch in new_post_composer.dart:237 is allowlisted as "the team picker is optional and the post can still be published without one", which is only true for `player_seeking_team` — `_post()` hard-requires a team for both team_seeking_* modes (lines 126-129).

---

## 19. [MEDIUM] The 17-screen retry sweep is guarded by an allowlist keyed on generic code shapes, so any ErrorRetry can be replaced by an excused shape anywhere in lib/

- **file**: `app/test/error_branches_have_retry_test.dart`:74


**Failure scenario**

The excused check is `allowed.keys.any((k) => body.contains(k) || lines[i].contains(k.split('\n').first))` (line 67). The keys are code fragments, not file paths: 'error: (e, _) => Center(child: Text(humanError(e)))', 'error: (e, _) => Text(humanError(e))', 'error: (e, _) => Center(\n' (whose split-first is the substring 'error: (e, _) => Center('), 'error: (e, _) => Padding(', 'error: (e, _) => ListView('. Replace lib/src/features/tournaments/presentation/tournament_page_screen.dart:48 - currently `error: (e, _) => ErrorRetry(...)` - with `error: (e, _) => Center(child: Text(humanError(e))),` and the sweep reports it excused under a reason that reads 'inline in a past-opponents sheet the user can close and reopen'. tournament_screens_test.dart:52 overrides tournamentOverviewProvider with a success, so no widget test touches that branch. A visitor whose phone drops signal opening a shared /tournament/:id link then sees a dead error string for the rest of the app's life, because the provider is not autoDispose - which is finding 39, reopened.


**Why it is real**

There are 22 ErrorRetry sites in lib/ (grep) and only six behavioural retry assertions in the whole test dir (matches, search, console, ball log, splash, innings break). Every other screen in the sweep is protected only by this source guard, and the guard excuses by shape rather than by location. Each of the five blanket keys currently matches exactly one line in lib/, so the allowlist reads as location-specific while behaving globally.

---

## 20. [MEDIUM] silent_failures_test guards finding 49's schedule half by the absence of one exact old comment, which a plain empty catch does not reproduce

- **file**: `app/test/silent_failures_test.dart`:55


**Failure scenario**

The three assertions are: absence of the literal `catch (_) {/* non-fatal: the match exists either way */}`, absence of the literal `catch (_) {/* non-fatal: the match is created regardless */}`, and presence of the string 'could not be messaged'. In start_match_screen.dart:119-121 the schedule write's handler is `catch (_) { missed.add('the date and ground could not be saved'); }`. Replace those three lines with a bare `catch (_) {}` and all three assertions still pass: neither old comment string is present, and 'could not be messaged' still exists at line 134 in the DM handler. A captain who taps 'Propose a match' from a dated looking-for post then gets a match with no date and no schedule, is shown no message, and both sides turn up on different days - exactly the half of finding 49 the test names in its own reason string at line 57.


**Why it is real**

Asserting the absence of a specific historical comment only detects a literal revert of that commit, not a reintroduction of the behaviour. The DM half is genuinely covered by the positive assertion on line 64; the schedule half has no positive assertion at all - nothing checks for 'the date and ground could not be saved' or for the snackbar.

---

## 21. [MEDIUM] pgTAP 107's restamp assertion cannot fail: reverting restamp_innings_strike to the hardcoded all-out of 11 passes the entire 872-test suite

- **file**: `backend/supabase/tests/107-fold-lockstep-invariant.test.sql`:71


**Failure scenario**

Assertion 6 is 'LOCKSTEP: restamp agrees with the fold about the live pair'. It captures deliveries.striker_id at seq=2, calls restamp_innings_strike, and asserts seq=2's striker is unchanged. seq=2 is the second ball of the innings, before any batter is out, so its striker is fixed by ball 1 alone and no all-out threshold can move it. I inserted `_all_out := 11;` immediately after the `_innings_fold_params` select in restamp_innings_strike - the exact pre-fix bug this file's header describes - and ran it: assertions 1-6 all reported 'ok', then I ran all 138 pgTAP files against the same mutation and NOT ONE failed. The control (restamp_innings_strike replaced by `begin return; end`) correctly failed 111-unit5-tie-and-restamp and 70-restamp-strike, so the harness discriminates.


**Why it is real**

The file's stated purpose is that all THREE folds agree, and the same mutation applied to compute_innings_cards DOES fail 107 (I verified) - so two of the three legs are pinned and the third is not. Anyone changing restamp's end-of-innings condition (or reintroducing a squad-size constant there) gets a green suite while the third fold silently disagrees about where a short-squad innings ended, which is precisely the class of divergence this file was written to make impossible.

---

## 22. [MEDIUM] pgTAP 144's 'this is the proof' assertion for the leaderboard cost fix matches only the join keyword, so the unfiltered CTE can be restored with the suite green

- **file**: `backend/supabase/tests/144-leaderboard-and-claim-cost.test.sql`:75


**Failure scenario**

The file explicitly says assertions 1-4 'hold with or without the fix ... This is the proof:' and then asserts `matches(pg_get_functiondef(tournament_leaderboard), 'join appearing')`. But the cost lives in how `appearing` is DEFINED, not in the join. I replaced the CTE body `appearing as (select mid from bat union select mid from bowl union select mid from fld)` with `appearing as (select id as mid from public.team_members)` - restoring exactly the pre-fix behaviour described in 20260805120000_leaderboard_and_claim_cost.sql:5-17 (a materialised temp relation holding one row per team membership in the entire database) - and ran all 138 pgTAP files: zero failures. The decoy assertion (line 64) still passes because 'Decoy' scored nothing and the leaderboard only lists players with runs/wickets/dismissals.


**Why it is real**

The regex is satisfied by the join keyword alone, and the file itself disclaims the four behavioural assertions as non-proof. So the only guard on finding 65's fix is a string that survives the regression. The endpoint is anon-callable with no caching on the public tournament page, which is why the cost was raised as a finding in the first place.

---

## 23. [LOW] A guest-claim request can be approved but never declined, so a bogus claim sits in the captain's inbox forever

- **file**: `app/lib/src/features/teams/presentation/claim_inbox_screen.dart`:103


**Failure scenario**

A stranger opens a public team page, taps "This is me" on a guest row and requests that guest identity — which, if approved, transfers that guest's entire batting/bowling history to them (approve_guest_claim rewrites team_members.profile_id). The captain opens Profile -> My teams -> Claim requests and sees "X wants to claim 'Rahul'". The row's only control is an Approve button; there is no Decline, no dismiss, no swipe action. The request stays `pending` and reappears on every visit to the inbox. The requester cannot withdraw it either — team_page_screen still renders "This is me" on that row, and request_guest_claim only re-opens the same pending row.


**Why it is real**

There is no reject/decline RPC in the schema: `grep -rn "guest_claim" backend/supabase/migrations/*.sql` returns only request_guest_claim and approve_guest_claim (20260615141401_rpc_guest_claims.sql, re-defined in 20260728130000_deleted_account_not_claimable.sql). The 'rejected' status exists but is only ever written as a side effect of approving a competing claim (20260615141401_rpc_guest_claims.sql, final UPDATE), so the single-claim case has no terminal state at all. identity_providers.dart:24-40 filters the inbox on `status = 'pending'`, so the row is permanent.

---
