---
type: memory
category: status
last_updated: 2026-07-07
---

# Work Status

## 📌 READ THIS FIRST (2026-07-07)

**The authoritative current state is `Projects/cricket-app/2026-07-07-fix-run-handoff.md`.**
Read that, then `Projects/cricket-app/CLAUDE.md`. Everything below this block is a
historical running log, newest-first; do not treat older entries as current.

- **ACTIVE: fixing a 100-finding adversarial penetration review**
  (`Projects/cricket-app/2026-07-07-penetration-review.md`; machine-readable at
  `/tmp/pitch_merged_findings.json`) under a standing `/loop` - the user's
  instruction is "don't stop until zero errors, re-run the review repeatedly, and
  verify on the iOS simulator as a real user".
- **~46 commits in the run** (`eacdd23`..`2e790f1`). Gates: backend **660 pgTAP /
  109 files**, app **analyze clean + 228 widget tests**, and **journeys A/B/C/D
  ALL GREEN on the iOS simulator for the first time** (run 15, `+5 All tests
  passed`, jd1..jd8 in `/tmp/pitch_shots`). The scoring frames are
  cricket-correct: a no-ball with byes reads 2/0 at Over 0.0, FREE HIT shows, and
  strike rotates on the odd bye.
- **RUN 16 RESULT**: journeys A/B/C/D/**K** green; **E failed** and the screenshot
  showed why - the wagon-wheel sheet ("Where did 1 run go?") opens after every
  scoring shot and SWALLOWED the next tap, so only the first of two balls was
  recorded and the failure surfaced two steps later as a wrong score. New shared
  `scoreRuns()` helper taps the run then skips the sheet (`a70b986`). Journey D
  never hit it because D scores through the Extras sheet, not the run pad.
- **Found by reading, this turn**: "Manage invites" listed usage + expiry and
  NEVER the invite code, although the provider had been selecting `invite_token`
  all along - so once the OS share sheet closed, a captain could not read,
  re-send or dictate that code, and it undercut the "Have an invite code?" entry
  added earlier in the run. Code now shows as selectable monospace, tapping the
  row copies the full link (`963c837`).
- **RUN 17: ALL SIX JOURNEYS GREEN** (`+7 All tests passed`) - A/B/C/D/E/K.
- **BUT reading run 17's frames found a real defect the green run hid.** The ball
  log showed `0.1 = 2 runs to Fix2` / `0.2 = 1 run to Fix1` while the DATABASE
  held the opposite and cricket-correct thing (seq 1 = 1 to Fix1, seq 2 = 2 to
  Fix2 after the single rotated strike). Cause: **postgrest-dart's `order()` is
  declared `{bool ascending = false}`, so a bare `.order('seq')` sorts
  DESCENDING** (verified in the package source). SEVEN call sites were written
  that way and every one wanted ascending - the ball log (labels computed by
  POSITION, so every over label was attached to the wrong delivery), DM threads
  (history backwards, new messages appended to the far end), post replies, the
  claim inbox and join-request queue (LIFO instead of FIFO), and the innings
  switcher (2nd innings before 1st, contradicting its own comment). Fixed in
  `c06c4c4` + `test/query_ordering_test.dart` proven RED. **This is the SECOND
  time a journey passed over a real defect - the assertion checked the total,
  which was right, and never looked at the arrangement.**
- **RE-REVIEW COMPLETE: 19 CONFIRMED, 12 REFUTED** (37 agents, 3.57M tokens).
  Full text in `Projects/cricket-app/2026-07-07-rereview-confirmed.md` (`3445319`)
  **including the refuted list - do not chase those.** Two claims I relayed
  before verification were REFUTED: the `next=` sign-in fix DOES work, and
  journeys A and K DO have assertions that can fail.
- **FIXED THIS TURN:**
  * **CRITICAL `00c17a8`** - `authGateProvider` (sync) watches `myProfileProvider`
    (async) and `when()` defaults `skipLoadingOnReload` to FALSE, so every JWT
    auto-refresh (~hourly, and on every resume from background) flipped the gate
    ready -> loading, the router re-ran its redirect, and the loading branch sent
    every non-public location to /splash - a TOP-LEVEL route outside the tab
    shell, so the shell and every branch navigator were torn down. A scorer
    mid-innings landed on Discover having touched nothing. Fix
    `skipLoadingOnReload: true`. `test/auth_gate_reload_test.dart` OBSERVES the
    default emitting loading, so it proves the mechanism, not just the fix - it
    needed a real async gap, because without one the reload resolves in one
    microtask batch and the intermediate state is invisible.
  * **HIGH `0065e20`** - the create-profile "Sign out" I added earlier this run
    did NOT leave the screen. The anonymous branch only moved people off SPLASH,
    so it returned null for create-profile. Signed out, still on the form, no
    back button, no tabs - and the form stayed LIVE over a fresh anonymous
    session, so Continue would have written a profile row for the wrong user.
    I had written a comment asserting it worked without verifying it.
  * **Ball log order CONFIRMED FIXED ON DEVICE** (run 18 frame: 0.1 = 1 to Fix1,
    0.2 = 4 to Fix2). Journey E now asserts the ARRANGEMENT, not just the total.
  * **HIGH cluster `a274db8`** - leaving a team was a ONE-WAY DOOR. The `left_at`
    tombstone was read by every re-entry path without filtering, so accept_invite
    returned the dead row and said "You joined the team" over a no-op,
    request_to_join said "you are already on this team", a departed guest's NAME
    was burned, and transfer_scorer would hand LIVE SCORING to a departed player.
    One idea fixed all five: a departed membership is REVIVABLE - re-entry clears
    left_at on the SAME row so all its match history stays attached. Test 117
    proved RED on exactly those paths. pgTAP now 672/110.
    (Two review dimensions DISAGREED on the last-captain guard; the test shows it
    is already correct in the reachable case, so that part is hardening, not a
    fix. Recorded as such.)
- **RUN 19: all six journeys green** with journey E now asserting the ball-log
  ARRANGEMENT, not just the total.
  * **2 HIGH `cff5d14`** - (a) a DEPARTED player haunted a resumed squad:
    invisible (off the roster), unremovable, counted in "N picked", and
    re-written on save. Prefill now only takes still-selectable players; proven
    RED (counter read 4 where 3 were pickable). (b) finishing a tournament
    fixture never invalidated tournamentOverviewProvider, so the organizer
    finished the last group game and Generate playoffs stayed disabled forever -
    the SAME stale-provider class, in a third place.
  * **2 MEDIUM + 5 dud assertions `9b1317b`** - the opponent sheet overflowed a
    375x667 phone by 93px with the keyboard up (fixed height + autofocus);
    opponentSearchProvider was a non-autoDispose family keyed per keystroke, so
    a FAILED search stayed cached for the session. And five of MY OWN assertions
    could not fail: journey D asserted the Undo/Swap/Retire buttons EXIST (the
    AbsorbPointer bug left them rendered but dead - it now asserts the striker
    actually changes), journey B waited on the always-present 'Discover' tab
    label and never checked the post was created, journey C's finder matched the
    SEARCH BOX it had typed into, pgTAP 112's post was excluded for being
    EXPIRED rather than by the match-date floor it names, and pgTAP 114 checked
    a bound with one row in the fixture.
  * **`47112d0` - THE STRENGTHENED ASSERTION PAID OFF ON ITS FIRST RUN.**
    Journey B failed and the frame showed the composer STILL OPEN after Post,
    with no visible reason. Two real things: (a) every submit form rendered its
    error AFTER the submit button, and the button is the last widget in a long
    scrolling form - so the message landed OFF-SCREEN below the fold and tapping
    Post appeared to do nothing. SEVEN forms did this (composer, create profile,
    edit profile, start match, toss, create team, create tournament); the error
    now renders above the button. (b) journey B never picked the REQUIRED flair,
    so `_post()` bailed every time - **journey B had never once created a post**
    and reported success for weeks, because its old wait was
    `settle(find.text('Discover'))`, the tab label present on every screen.
  * **run 21 found the next layer of the same test bug**: my flair tap used
    `find.widgetWithText(ChoiceChip, ...)` but the flair options are `FlairChip`
    inside a `GestureDetector` - never a ChoiceChip - AND `tapScrolled` only ever
    scrolled DOWN, so it walked to the bottom of the composer past chips that sit
    near the TOP. tapScrolled now searches both directions.
  * **WRITTEN, NOT YET VERIFIED** (device was busy; needs `supabase db reset &&
    supabase test db`): `20260707210000_notify_only_present_admins.sql` +
    `tests/118-notify-present-admins-only.test.sql` (departed admins kept getting
    their old team's join-request/claim notifications), and an app-side composer
    fix refusing a match time the feed would hide (the picker offered YESTERDAY
    while discover_posts floors at now-6h, so the app created invisible posts).
    **Run the gate before trusting either.**
  * **ALL 19 CONFIRMED FINDINGS ARE NOW CLOSED** (`e626518` closed the last one:
    departed admins receiving their old team's join-request/claim notifications,
    test 118, verified - pgTAP now **678 / 111 files**).
  * **`e626518` also shipped a FEATURE the frames revealed**: every layer
    supported a post title except the one that creates it. `looking_for_posts
    .title` exists, `create_looking_for_post` takes `_title`, `discover_posts`
    returns it, and the feed card PREFERS it over the mode label - there was no
    input. So every ad was headlined "Need a team" instead of the poster's own
    words, on a feed whose whole job is conveying intent. Found by LOOKING at
    run 22's frame, which showed the created post as a generic card.
- **RUN 27: the group split WORKS** (frame: G1/G2 in A, G3/G4 in B, Generate group
  fixtures enabled and green). My assertion was wrong again - I waited for the
  tally "A has 2 and B has 2", but that line belongs to the "You need 4 teams"
  WARNING, which only renders while the requirement is UNMET. Waiting for it was
  waiting for a string that by definition disappears when you succeed. Journey G
  now polls until the button is ENABLED and asserts the warning is GONE (`4b6386b`
  then the follow-up). **Three iterations on journey G, three mistakes of MINE,
  zero product defects found by it so far.** Run 28 verifying.
- **RUN 26 (journey G's first run) CAUGHT ME REPEATING MY OWN LESSON.** The frame
  showed all four teams still in group A ("A has 4 and B has 0") and Generate
  group fixtures correctly DISABLED - no fixtures were ever generated. Three of
  my mistakes, all the family I have been fixing elsewhere all session:
    1. the group chips are in each team's `ListTile.trailing` **Wrap**, not a Row
       - I inferred the widget type from a SCREENSHOT instead of reading the
       source, the second time this session (flair chips were FlairChip, not
       ChoiceChip);
    2. the tap was wrapped in `if (bChip.evaluate().isNotEmpty)`, so finding
       nothing was indistinguishable from success - **I wrote a learnings entry
       about exactly this guard two turns earlier and then used it again**;
    3. the only post-generate assertion was `expect(PostgrestException,
       findsNothing)` - absence of an error, not presence of an outcome, so it
       passed because nothing happened.
  Fixed in `4b6386b`: chips found via the ListTile, unconditional tap, the
  journey reads the screen's own tally back ("A has 2 and B has 2"), asserts the
  button became ENABLED, then asserts the "Group fixtures" section appears -
  a heading VERIFIED in the source (my first guess, "Fixtures", exists nowhere).
  Run 27 is verifying.
- **STABILITY ESTABLISHED: runs 24 AND 25 both all-seven-green** (6:41 and 6:39,
  no timeout frames). Run 23's mass failure is confirmed transient.
- **JOURNEY G ADDED (`4344210`)**: journey A only ever added TWO teams, so
  `Generate group fixtures` - the step that makes a tournament playable at all -
  had NEVER been driven on a device, nor had the "You need 4 teams" gating copy.
  G creates four teams, splits both groups, generates fixtures, and pins both
  gates honestly (disabled with no teams; playoffs disabled with group games
  unplayed). That playoffs assertion is the closest thing to a test the
  tournamentOverviewProvider fix has. **Still uncovered: completing all four group
  games through the console, and a TIED semi via resolve_tied_fixture (that one
  belongs in pgTAP, not a device journey).** Run 26 is verifying G now.
- **FULL 12-FRONT WHOLE-SYSTEM REVIEW #2 RUNNING**: `wf_f990aa01-feb`. Fronts =
  sql, rls, cricket, state, nav, errors, realtime, lifecycle, scale, platform,
  tests, privacy. Each finding faces TWO skeptics with different lenses (claim
  accuracy vs reachability) and survives only if NEITHER can refute it, plus a
  completeness critic at the end. The prompt lists all previously-fixed defects so
  agents hunt what two reviews MISSED. **Read its confirmed/refuted split before
  acting on anything.**
- **(superseded) RUN 24: ALL SEVEN JOURNEYS GREEN in 6:41, 0 failures** - so run 23's six
  failures WERE transient, not a regression. The likely trigger: run 23 was
  launched immediately after `supabase db reset && supabase test db`, and
  `supabase test db` hammers the stack, so the app's first queries hung and every
  spinner outlived pumpAndSettle. **Operational rule: let the stack settle after
  a reset+test before launching a device run.** Run 25 is the second consecutive
  confirmation (do not declare stability on one green run).
- **VERIFIED ON DEVICE (run 24 frame)**: the feed card now reads "Need an
  opponent <run>" as its headline with the flair and mode label beside it - the
  Headline field works end to end.
- **`ensureSignedOut` now FAILS with a frame** instead of giving up silently
  after 12s; that silence is precisely why run 23 reported six failures in five
  unrelated places rather than one at the sign-out.
- **(superseded) RUN 23 WAS A FALSE ALARM - 6 failures, ~67 min, and NOT a code regression.**
  Row counts after it: **1 user, 2 teams** - so journey A created its teams and
  then failed at "Add my team", and journeys B/C/D/E/K never signed up at all,
  hanging with `pumpAndSettle timed out` (which is what a spinner that never
  stops looks like). The local stack was later confirmed HEALTHY (all six
  containers up, `/rest/v1/teams` in 66ms), so the backend was not the cause.
  **I initially mis-called it as "docker is hung" because `supabase status -o
  json` was slow and my `docker ps` probes queued behind it - docker was fine.**
  Run 24 is the single-purpose diagnostic. DO NOT record run 23's failures as
  product defects until a clean run reproduces them.
  Prime suspect to check first: the `skipLoadingOnReload: true` change interacts
  with the sign-OUT window, where `session == null` is neither anonymous nor
  ready - the gate may now hold a stale `ready` (or flip to `needsProfile`) and
  strand the app instead of showing splash. `ensureSignedOut` polls for 'Sign in'
  and RETURNS WITHOUT FAILING after 12s, which would hide exactly that.
- **`5fef590`**: the composer feed-floor rule is now a top-level pure function
  with 5 tests (5h ago accepted, yesterday refused, constant pinned to the SQL) -
  it shipped untestable last turn and I said so; now it is covered.
- **NEXT (all confirmed findings done)**: re-run the FULL 12-front review and
  repeat until zero; journeys F-J (§7 - G is the only real end-to-end proof for
  the tournamentOverviewProvider fix, which still has no test); the SHADOW PUSH.
- **(historical) STILL TO FIX from the confirmed list** (work down
  `2026-07-07-rereview-confirmed.md`): the whole `left_at` cluster (leaving a
  team is irreversible; accept_invite no-ops; request_to_join says "already on
  this team"; a departed guest's NAME is burned; transfer_scorer can hand
  scoring to a departed player; last-captain guard counts departed captains), a
  departed player stuck in a resumed squad, tournamentOverviewProvider never
  invalidated after a fixture ends (playoffs ungeneratable), the discover
  match-date floor hiding posts the composer happily creates, the opponent sheet
  overflowing on a 375x667 phone, opponentSearchProvider caching a failed search
  per keystroke, and four of my own test assertions that cannot fail.
- **(earlier) THE RE-REVIEW FOUND A LOT** - raw findings dumped to
  `Projects/cricket-app/2026-07-07-rereview-raw.md` (`71865e7`) so they survive
  compaction; **read the workflow's final confirmed/refuted split before acting,
  several were refuted.** The headline claims:
    * CRITICAL - `authGateProvider` (a SYNC Provider) watches `myProfileProvider`
      (async). Confirmed to exist; it uses `.when()` so it will not crash, but
      the claim is a token refresh flips it to `loading` and the router then
      wipes the nav stack to /splash. NEEDS VERIFYING.
    * HIGH - the `next=` sign-in fix from this run **does not fire in the real
      flow**: the `loading` branch returns a bare `/splash` and drops `next`.
    * HIGH - the create-profile "Sign out" escape **does not escape**.
    * HIGH - a whole cluster of `left_at` consequences I did not chase:
      accept_invite silently no-ops for a departed member, request_to_join says
      "already on this team", a departed guest's NAME is permanently burned,
      transfer_scorer can hand live scoring to a departed player, and the
      last-captain guard counts departed captains.
    * HIGH - several of MY OWN journey assertions cannot fail (D's
      Undo/Swap/Retire, A's tournament step, B's post-created check).
    * HIGH - finishing a tournament fixture never invalidates
      tournamentOverviewProvider, so playoffs can never be generated (the same
      stale-provider class as the squad handoff).
- **IN FLIGHT when this was written**: journey run 18 (confirms the ball-log
  order on device) and journey run 17 (`/tmp/journeys_run17.log`,
  all six journeys with the wagon fix) and journey run 16 (`/tmp/journeys_run16.log`,
  adds journeys E ball-log corrections and K anonymous browsing) and a
  six-dimension adversarial re-review Workflow of everything the fix run changed
  (run id `wf_528f0fb6-945`; dimensions = sql, left_at, providers, navigation,
  matchsetup, tests; every finding checked by a skeptic that tries to refute it).
  **Read both results before doing anything else.**
## 2026-07-07 (later) - the device-found defects

**Journeys A-D went fully green on the simulator for the first time (run 15).**
Everything below was found in this stretch; the two that mattered most were found
by DRIVING the app, not by any test.

**THE SQUAD HANDOFF (flow-breaking, would have shipped).** A scorer picked their
squads, tapped "Next: toss", and the Striker/Non-striker dropdowns were EMPTY -
the match could not be started at all. Cause: the squads screen watches
`matchSquadProvider` from the moment it opens, so the provider was alive holding
its pre-write value (an empty squad); `pushReplacement` builds the toss screen in
the same frame, so the listener count never hits zero and the new screen inherits
the stale list. `flutter analyze` and 228 widget tests were green the entire
time. Fixed in `match_squads_screen` + `toss_openers_screen` (same trap one step
later with `matchProvider`). Regression test `squads_to_toss_test.dart` PROVEN RED
first (0 items offered). A full audit of every write-then-navigate site found
only those two.

**The opponent picker** was `from('teams').select('id,name,city').order('name')` -
no limit, no filter. The whole teams table downloaded on every visit to
Start-a-match and poured into a DropdownButton. Replaced with a
`search_opponent_teams` RPC (recent opponents by default, bounded name search
otherwise, capped at 25) plus a search sheet.

**Leaving a team never worked** for anyone it mattered to: nine FKs point at
`team_members` with NO ACTION, so the raw delete raised 23503 for anyone who had
ever played. Now `left_at` soft departure + a `leave_team` RPC + both authz
helpers require `left_at is null`. **My own test caught a NULL-logic hole in the
RPC I had just written**: a guest row has `profile_id` null, so
`not (false or NULL)` is NULL and the guard never fires - any user could have
removed any guest from any team. `coalesce(..., false)`.

**OAuth could never come back.** `io.supabase.pitch://login-callback` was
registered on NEITHER platform - no CFBundleURLTypes, no intent-filter. Sign-in
opened a browser and the callback had nowhere to land. Both registered; verified
in the built Info.plist.

Also: overs sanity (0 overs made an unplayable match), posts expiry + a feed
match-date floor, `did_not_bat` listing dismissed players, storage bucket
enumeration (**verified empirically both ways** - old policy lists every object,
new returns [], public URL 200 either way), `insert_ball` anon revoke, duplicate
GlobalKey across the two share sheets, iPad `sharePositionOrigin` on every share,
notification dead taps, deep-link stranding, sign-in destroying the invite
(`next=`), an invite-code entry point, and a sign-out escape from create-profile.

**TWO MISTAKES OF MINE, now rules in learnings.md:**
 1. I ran `supabase db reset` WHILE a device journey was live, wiped its data
    mid-run, and the failure surfaced as a fake app bug on a distant screen.
    Check `pgrep -f 'flutter drive'` before any reset.
 2. I put backticks in a `git commit -m "..."` string and the shell EXECUTED
    them. Always `git commit -F - <<'MSG'`.

**HONEST LIMIT**: the Apple sign-in entitlement is WIRED (xcodebuild
-showBuildSettings confirms CODE_SIGN_ENTITLEMENTS) but NOT PROVEN - a simulator
build is ad-hoc signed and never applies an entitlements file, so it cannot be
verified without a signed device build (needs the user's Apple credentials).

**NEXT, in order:** (1) read `/tmp/journeys_run16.log` AND the screenshots, and
the re-review Workflow result; (2) fix whatever they confirm; (3) journeys F-J
(handoff §7); (4) the SHADOW PUSH (reset local to the hosted 2026-06-27 schema,
populate, apply all pending migrations, prove none abort); (5) re-run the review
until it returns zero.

**STILL USER-ONLY:** rotate `dev@pitch.local`/`password123` on hosted (a live
credential inside the friend's APK - most urgent), run the hosted `db push`,
rebuild the APK, and put up pitch.app/privacy + /terms.

- **DONE**: Units 1 (both criticals), 2a/2b/2c (high backend), 3a/3b (high
  frontend), 4a/4b/4c (primitives + humanError + error-UX), 5a/5b (medium
  structural), 6a (release config), 7a (pgTAP rescoping), plus the device-found
  Discover build-phase crash (3 attempts).
- **JOURNEY D added** (`d9eceb4`): score a match through the console - drives the
  no-ball-with-byes enum bug, the penalty/overthrow composer, and asserts
  Undo/Swap strike/Retire are REACHABLE (they were dead inside the AbsorbPointer).
  First device run stalled at the toss and the SCREENSHOT found a real defect
  (`6c0da59`): the "Opening pair" section was gated behind
  `if (battingTeam != null)`, so a first-time scorer saw only Toss winner /
  Elected to / Start match, tapped Start, and was told to pick openers they had
  never been shown - the form revealed its requirements only on failure. Now
  always shown, with a hint before the toss is decided. (My sloppy test - tapping
  Start with nothing selected - is what surfaced it.)
- **JOURNEY D is still being stabilised** (the APP is fine - jd2_squads.png shows
  batting order auto-numbered 1/2/3 and the Captain/Wicket-keeper pickers working,
  i.e. SCOR-13 delivering on device). Two TEST traps found and fixed: tapping a
  DropdownButton's hint text does not hit-test (menu silently never opens ->
  misleading "Bad state: No element"), and a fixed 600ms wait is too short for the
  overlay route - the helper now polls ~7s and screenshots on failure.
- **WRITTEN BUT NOT YET TESTED** (needs a `db reset`, which would break the
  in-flight journey run): `20260707160000_posts_expire.sql` +
  `tests/112-posts-expire.test.sql` - MEDIUM discover-posts-never-expire. Adds a
  real expires_at default (dated post dies the day after the match, undated after
  14 days), backfills nulls, a match-date floor in the feed, and recency in the
  ORDER BY so played matches sink. **Run `supabase db reset && supabase test db`
  before trusting it.**
- **NEXT**: finish Journey D, then journeys E-K (handoff §7), remaining medium +
  low findings, the shadow push, then re-run the 12-front review until zero.
- **USER-ONLY, most urgent**: rotate `dev@pitch.local`/`password123` on the hosted
  project (real credentials, shipped in the friend's APK), then the hosted
  `supabase db push` (**77 pending migrations**), then rebuild the APK.


---

Everything before the 2026-07-07 fix run now lives in
`archive/work_status-pre-2026-07-07.md` (rule 13: this file had reached ~1400
lines). Nothing was deleted.
