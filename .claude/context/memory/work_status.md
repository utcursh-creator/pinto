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
- **IN FLIGHT when this was written**: journey run 16 (`/tmp/journeys_run16.log`,
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
