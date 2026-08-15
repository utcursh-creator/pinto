---
type: memory
category: status
last_updated: 2026-08-04
---

# Work Status

## 📌 READ THIS FIRST (2026-07-07)

**The authoritative current state is `Projects/cricket-app/2026-07-07-fix-run-handoff.md`.**
Read that, then `Projects/cricket-app/CLAUDE.md`. Everything below this block is a
historical running log, newest-first; do not treat older entries as current.

## 2026-08-04 - review #2 fix run, scoring-console cricket-rules cluster

Under a standing `/ralph-loop` (unlimited iterations, NO completion promise - it
re-feeds the same prompt forever; the user should know it needs
`--max-iterations` or `--completion-promise` to ever self-terminate).

Working `Projects/cricket-app/2026-07-28-review2-findings.md`, re-verifying each
finding before acting (~60% of that file was REFUTED by the skeptics).

- `d734bc4` **a wicket can fall off a wide or a no-ball - the console could not
  say so.** `_wicket()` always sent a legal delivery, so a stumping off a wide
  (a T20 staple) and a run-out off a no-ball were unrecordable. Scoring them as
  ordinary dismissals loses the extra run AND burns a legal ball, so the over
  ends a delivery early and every later over is misattributed. The sheet now
  asks what the delivery was and narrows the dismissal list to what the Laws
  allow. A free hit that is also a wide binds BOTH guards, so `_typesFor()`
  intersects. **The server half of this finding was REFUTED** - `record_ball`
  already validated correctly; pgTAP 125 pins the uncovered half, that the FOLD
  counts these deliveries right.
- `80adbb6` **a first-ball wide locked the bowler out of his own over.**
  `_afterBall` used `legal % bpo == 0`; a wide moves nothing, and right after an
  over ends the count is already a multiple - so the console re-declared the
  over over, cleared the bowler, and filed the man who had just started as
  `_lastOverBowlerId`, which the picker shows as "Bowled last over" and refuses
  to select. Now compares against the count from before the ball.

- `63f87f3` **the console was the last screen still shouting Postgres at the
  user.** humanError() covered 78 sites but the console kept four raw
  `_toast('$e')`, so a failed ball showed a PostgrestException dump - the only
  feedback a scorer gets, mid-match, standing at the rope. The CONTROL is the
  important half: our RPCs raise P0001 with copy written for this user ("bowler
  cannot bowl consecutive overs"), so a blanket "Something went wrong" would be
  a regression dressed as a fix. Swept the app afterwards - the console was the
  last holdout of the class.
- `18bae73` **one correction fired 71 realtime broadcasts.** MEASURED by
  counting realtime.messages on a 30-ball innings: ordinary ball 1 (correct),
  delete_ball 15, insert_ball 71. The two-pass negate/restore renumbering fires
  the per-row trigger on every shifted delivery, and each message re-folds the
  WHOLE innings on every viewer. Fixed with a transaction-local GUC
  (`pitch.suppress_delivery_broadcast`, is_local => true) that the correction
  RPCs set while shuffling, plus one `emit_delivery_broadcast` at the end.
  Re-measured 71 -> 1. The control - ordinary scoring still emits exactly 1 -
  matters more than the fix, since over-suppressing would silence live scoring.

- `2a67a21` **a dropped connection told the scorer their match was never set
  up.** Console + ball log gated only on `isLoading`; an errored provider is not
  loading and has a null value, so it fell through to "No innings yet. Finish
  setup first." The obvious response - re-run setup - creates a SECOND innings
  on a live match. Classic instance-vs-class: the INNER inningsStateProvider had
  a good error branch already, the three OUTER ones did not. Swept after: those
  two files were the only users of the pattern.
- `b6a4640` **a player who actually played for your club could never rejoin.**
  `on conflict do nothing` silently skipped the tombstone while the request was
  marked approved anyway, and the consumed request made the lockout permanent.
  **My first analysis was incomplete and the test caught it**: leave_team HARD-
  deletes a member with no match history and only tombstones one who HAS played,
  so the first test version passed against the broken function. Guard confined
  to tombstones by `where left_at is not null`, proven discriminating (without
  it, approving a stray request demotes a sitting captain).

- `3004ed6` **a short match with few bowlers could not be scored to the end**
  (review #2 finding 13). The picker enforced the RAW `max_overs_per_bowler`
  (ceil(overs/5)); the server enforces `greatest(rule, ceil(overs/squad_size))`
  via `_bowler_over_cap` so a small bowling side can still bowl the innings out.
  Measured: 10-over match, rule 2, effective cap 4 - so after 6 overs every
  picker row read "At over limit", the pad stayed disabled, and the match was
  unfinishable. Client now ASKS the server (`_bowler_over_cap` is SECURITY
  INVOKER and already granted to authenticated; verified over real HTTP that
  PostgREST exposes the underscore name). Watched not read, or the first open
  silently means "no quota".

- `42d0f89` **deleting an over's last ball stranded the console on the wrong
  bowler.** After an over, `_lastOverBowlerId` = X. A ball-log delete reopens
  the over but the console never reconciled, so the picker branded X "Bowled
  last over" and the only selectable bowlers were wrong - picking one miscredits
  the rest of X's over permanently via the career re-fold. `_undo()` already had
  this recovery; it lived in that ONE handler instead of reacting to the fold.
  Moved to a `ref.listen` on `inningsStateProvider` and deleted the undo copy,
  with an explicit undo REGRESSION GUARD. Sabotaging the listener fails 6/8
  including that guard - which is what proves the deleted code's behaviour is
  actually carried by the new mechanism.

- `5b683c3` **the hottest queries had no index that could serve them** (review
  #2 findings 20/21/29/60 + 21/74/83). pg_trgm GIN on the three ILIKE search
  columns; partial index on matches(created_at) where status is live - the
  public Watch-live list is ANON-reachable and seq-scanned every match ever
  played; matches(team_a_id/team_b_id); match_squad(team_member_id) (the only
  index naming it had it SECOND in a composite). pgTAP 128 asserts the PLANNER
  USES each index for the real predicate - "an index exists on display_name"
  would pass while ILIKE still scanned. Also capped 4 unbounded reads, with the
  guard testing BOTH directions (capping a match squad is a correctness bug).
  KNOWN GAP: the DM thread is capped at 200, not paginated.

- `e26294f` **the scoring engine's rules were bypassable straight off the
  table** (finding 56, plus a bigger hole found verifying it). deliveries,
  innings and match_squad each had an ALL policy for the scorer PLUS the grants,
  so every cricket rule (consecutive overs, bowler quota, legal dismissals, the
  seq token, the three folds) could be bypassed with one HTTP call - and those
  rows are tournament standings and other players' career records. All 22
  writers are SECURITY DEFINER, so revoking the grants closed the side door.
  Also revoked matches DELETE (delete_match's tournament guard was decorative).
  FALLOUT: 28 pgTAP files seeded deliveries directly and now elevate-then-
  restore; 2 do it inside plpgsql helpers; and the tournaments DEVICE JOURNEY
  seeded directly while claiming to use "the RPCs" - fixed, or the next device
  run would have failed.

- `42ed763` **every reply body in the database was readable by any account**
  (finding 63). `post_replies` was `using (true)` + a table grant, so one
  paginated GET returned every reply ever written - the field where people type
  their phone number and which gate they meet at - joined to its author. And
  `post_detail`'s entire WHERE was `p.id = _post_id`, SECURITY DEFINER, so it
  resolved any post to a name, place and time. Together: a permanent global
  index of who wants a game, where, with whom. Both now use ONE
  `post_is_visible()` (your own ad forever / live on the feed's terms / you are
  already in the thread), coalesced to false so a missing post is invisible.
  7 of the 9 assertions are CONTROLS - over-tightening breaks Discover.

- `53b45f1` **account deletion did not delete the messages or the photos**
  (findings 35 + 52). The dialog said "permanently removes your profile, posts
  and messages"; it removed posts and NOTHING else - every DM body and every
  post_reply survived verbatim, and the avatar/post photos stayed in PUBLIC
  buckets at their original URLs. The line held: the friend's side of a
  conversation survives. **Photos cannot be deleted from SQL** - Supabase
  rejects direct DELETE on storage.objects ("Use the Storage API instead"), so
  the client removes them BEFORE the RPC (which revokes auth and would strand
  them), and a failure is deliberately not swallowed.

- `7d60e02` **DEVICE PASS after 12 fix units** (iPhone 17 sim, live local
  Supabase, re-seeded). **8/8 journeys green.** Read the frames, not just the
  result: the console gates the pad correctly, jd6 still shows a no-ball with a
  bye as 2/0 at Over 0.0 with FREE HIT and strike rotated. Added jd4b/jd4c so
  the WICKET sheet is actually looked at - choosing Wide narrows "How out?" from
  8 to the 4 the Laws allow, resets a stale "Bowled", relabels the counter to
  "Extra runs run" and reveals Fielder. The sheet FITS on a real phone: the
  scroll needed in the widget test was a 600pt-viewport artifact, not a defect.

- `c926bb4` **deleting the organizer's account froze every tournament they
  ran** (finding 36). All six management RPCs gate on `organizer_id =
  auth.uid()`, no transfer-organizer RPC exists, and the write policy is the
  same condition - so a half-finished bracket could never reach a final. SAME
  SHAPE as the sole-captain bug: hand it on rather than refuse the deletion.
  Goes to the longest-standing captain of the longest-established enrolled club.
  Controls: a COMPLETE tournament is left alone, an empty one strands nobody.

- `68575f4` **a search that failed once could never be retried** (findings
  33/64/86). `searchProvider` is keyed by the query string and was NOT
  autoDispose (riverpod 3 FutureProvider defaults to false), so every prefix
  leaked for the session and a failed query cached AS AN ERROR - retyping the
  same name, the one thing a user will try, re-read the dead element. Now
  autoDispose + a real retry. The rule is "free-text-keyed families must
  autoDispose; ID-keyed ones must NOT" - opponentSearchProvider was already
  correct, and caching a match by id is the point.

- `a50adc7` **the refresh token was going into the user's Google backup**
  (finding 37). Android Auto Backup is ON unless the manifest says otherwise;
  supabase_flutter persists the session (refresh token included) in app-private
  storage. Now allowBackup=false + dataExtractionRules excluding every domain
  from BOTH cloud-backup and device-transfer (allowBackup alone does not stop
  device-to-device on Android 12+). Verified in the MERGED manifest and inside
  the built APK, not just the source. **iOS iCloud backup is NOT fixed** -
  smaller exposure, separate work, stated in the commit rather than glossed.
- Finding **57 is a DUPLICATE** of the CRITICAL closed earlier (pgTAP 121
  assertion 3 pins it) - no work needed.

- `526fcb4` **the discover feed returned every open ad in a 50km radius**
  (finding 58). The radius clamp bounds DISTANCE, not rows - 50km around a city
  is thousands of ads on every open and pull-to-refresh. Now a clamped page
  (default 100, floor 1, ceiling 200). DROPped before recreating (new arity =
  OVERLOAD = PostgREST 300); verified one definition and both client call
  shapes over real HTTP. Controls keep it NEAREST-first - bounding without
  preserving order turns "games near you" into "an arbitrary hundred".

- `480f765` **pasting the tournament invite reported a valid code as already
  used** (finding 46). The shared message is TWO sentences with a newline;
  `split('/join-tournament/').last` kept the newline and the second sentence,
  which survives as one URI segment - so the screen loaded, the RPC failed, and
  a good invite was called used. Trailing slash gave an empty token because the
  guard checked the RAW INPUT, not the derived one, landing on a route that
  matches nothing. Two parsers for one job, only one right -> now one shared
  `pastedToken(input, marker:)`.

- `4b0fb14` **"batters had crossed" was thrown away for obstructing**
  (finding 80). The console collects and sends `crossed` for obstructing, but
  all three folds gated the swap on `run_out` alone - while their OWN
  who-is-out line already read `in ('run_out','obstructing')`. The
  inconsistency was INSIDE each function. Result: wrong ends, and since strike
  is cumulative, every later ball credited to the wrong batter, then restamped
  onto every stored delivery. All THREE folds changed together (pgTAP 107 pins
  their agreement).
- LOW findings **74, 78, 83, 84, 86 were already closed** by earlier units in
  this run - checked, not assumed.

- `61aff0c` **a hurt batter at the last pair stayed on strike after walking
  off** (finding 85, both halves). retire_batter's guard was copied from
  record_ball, where the last-wicket relaxation is safe BECAUSE the wicket ends
  the innings - a retired hurt counts no wicket, so nothing ended and the folds
  left the pair untouched; every later ball was credited to someone who had
  left the field. Rule is now: somebody must come in unless the retirement IS
  the last wicket, which only a retired OUT can be. CLIENT mirror: the Retire
  button was dead whenever the dropdown was empty, so a genuine last-pair
  retirement was unrecordable. Test 101 pinned the OLD message; behaviour
  unchanged, copy corrected.

- `f5b94ea` **a no-ball that went for byes was not charged to the bowler**
  (finding 72). Law 21.13: runs off a No ball the bat did not strike are NO BALL
  extras, and the whole No ball is debited to the bowler. Fold charged the
  penalty only and bucketed the runs as byes, so the card read "nb 1, b 2" -
  byes off a delivery from which byes cannot be scored. Innings total was never
  wrong, which is why it survived. **Changed an EXISTING test's expectations**
  (30-fold-extras asserted "byes/leg-byes never charged" as a blanket rule) -
  the fold and its test encoded the same misunderstanding. **NEEDS A CRICKETER'S
  SECOND OPINION** - it rests on a Laws reading, and is a two-line revert.

- `c9bd9c3` **viewers kept seeing "Live now" through the whole innings break**
  (finding 77). `_breakMarked = true` was set BEFORE the await and the call
  ended in an EMPTY `.catchError`, so one blip at the interval (when phones
  come out - the likeliest moment) left the public status wrong for the whole
  break, unretried, with the scorer never told. Now visible + retryable, and
  deliberately NOT auto-retried: un-latching in the handler would re-fire on
  every rebuild, trading silence for a storm. CONTROL pins that a successful
  write still happens exactly once.

- `5be66be` **the penalty switch told scorers to use it for the one case it
  gets backwards** (finding 79). Subtitle said "deliberate short run", which
  penalises the FIELDING side, while the control always credits the batting
  side - a 10-run swing that can decide a chase. `extra_penalty` only accrues
  to the innings being folded, so penalties AGAINST the batting side are NOT
  MODELLED; inventing that schema is a feature, not a LOW fix. Copy now states
  the direction and names the short run as the case NOT to use it for.

- `2e3b3fd` **three controls that pointed nowhere** (findings 82/75/71, one
  unit - same shape: the app told somebody to do a thing it had not given them
  a way to do). Toss error said "Tap Edit squads below" with no such control
  anywhere in lib/ -> the button now exists and navigates. GoRouter had no
  errorBuilder, so a dead deep link showed Page Not Found whose Home button
  pushes '/' which this app does not define -> a real error page offering
  Discover. Approving a guest claim refreshed the inbox but not the roster, so
  a team page kept offering "This is me" on an already-claimed membership.

Gates: **pgTAP 796 / 129 files**, analyze clean, **336 widget tests**, **8/8
device journeys**, Android debug APK builds.

- `9b20c9e` **a failed location read published your ad in the wrong city**
  (finding 70 - the LAST confirmed item). `.value` is null for BOTH "unset" and
  "read failed", so the feed pinned to a fallback city silently AND the composer
  published the ad geotagged there - permanent, and nobody near the author ever
  sees it. I had set this aside as a design call; re-reading it, the composer
  half is data corruption, which decided the scope. Composer now refuses to
  guess, Retry re-reads the home ground, and the feed says when it is guessing.
  A genuinely UNSET home still falls back - that is existing product behaviour
  and a different question.

Gates: **pgTAP 796 / 129 files**, analyze clean, **339 widget tests**, **8/8
device journeys**, Android debug APK builds.

## CORRECTION (2026-08-05): I reported the list DONE too early
The findings doc's confirmed/refuted split was LOST, so there is no enumerable
"confirmed list" - the header says re-verify all 87. I had been working from a
mental subset. A systematic pass over all 87 is now on disk at
`Projects/cricket-app/2026-08-05-review2-audit.md`:
**55 CLOSED, 1 REFUTED (28), 1 USER-ONLY (4), 30 OPEN.**

- `2c94aba` **NRR ignored the match's over length, so the wrong team qualified**
  (finding 67, the top of the open list). `legal_balls / 6.0` hardcoded at both
  sites; balls_per_over is a real column create_match accepts. The error does
  NOT cancel - measured +6.000 where the truth is +8.000 on a 10x8 match - and
  NRR is the tiebreaker generate_playoffs seeds from. Best control came free:
  pgTAP 76 pins NRR=1.75 for a 6-ball tournament and still passes, proving the
  change is a no-op at six.

- `31131a7` **four tests that could not fail now can** (findings 32/50/69/81).
  The no-ball enum lock tested its OWN copy of the mapping; the recordBall
  contract asserted a constructor tearoff was non-null; the credentials test
  computed the prefill itself and asserted on its own arithmetic; the location
  oracle compared identical expressions and held vacuously on an empty result.
  All four proven by SABOTAGE - reverting the real bug fails the new test and
  failed none of the old ones. **My first attempt at 81 was itself wrong**: I
  claimed the radius floor defeats a pinpoint probe, sabotaged the floor, and
  the test still passed - `_snap_geog` grids BOTH post and probe so a same-cell
  distance is 0. Added a separate ~1.6km probe that DOES exercise the floor.

- `79b16c4` **Undo proved nothing, and a silent guard could hide the same
  again** (findings 45 + 18). Journey D asserted only that no "Could not undo"
  toast appeared - which is EXACTLY what a dead button produces. **My first fix
  was wrong and the device caught it**: I asserted the OVER changed, and the run
  failed with 'Over 0.2 - CRR 21.0' identical both sides. Correct behaviour -
  the last write before Undo is the strike SWAP, an event row not a ball, so it
  moves neither over nor score. Now asserts the striker is restored, which is
  provably discriminating (the line above asserts the striker CHANGED, so a
  no-op cannot satisfy both). 18 was already fixed - jg2_groups_split.png
  proves it - but its SILENT GUARD (`if (chip.isNotEmpty)`) was still live in
  journey A and is now an assertion. 8/8 green after.

- `60184df` **ticking a whole roster silently made it a 13-a-side match**
  (finding 53). all_out = squad_size - 1 with no upper bound on the squads
  screen, so a 13-man squad does not close at 10 wickets and "won by N wickets"
  is computed off 12 - persisted into matches.result.note forever. **Did NOT
  add a hard cap**: 12/13-a-side games are real and the backend supports them
  deliberately (squad_size in matches.rules, pgTAP 76/77 rely on it). The fold
  is right for the data; the UI let that data mean something unchosen. Now
  states the consequence in wickets. Control catches warning at >10.

- `aff06c9` **an avatar could report every viewer's IP to whoever set it**
  (finding 62). photo_url/logo_url/image_urls were arbitrary client strings, so
  an attacker points theirs at a host they control, joins a public squad, and
  every roster/inbox/leaderboard render leaks the VIEWER's IP, UA and a
  timestamp - including logged-out visitors, since photo_url goes to anon and
  the public routes bypass the gate. **The host is no longer stored**: a
  write-time trigger normalises to `/storage/v1/object/public/BUCKET/NAME` and
  the client resolves against its OWN origin. Shape-checking alone would have
  been theatre (anyone can serve that path), so the object must EXIST in our
  storage too. 58-post-attachments seeded `https://x/a.jpg` - the exact shape
  now refused - and was made honest.

- `6223e6e` **correcting the last wicket left the match saying "innings break"
  forever** (finding 61). Break written once; a ball-log delete reopens the
  innings but nothing wrote the status back (mark_innings_break only fires on
  'live', and innings_break -> live happens only in start_innings), and
  `_breakMarked` stayed latched. Viewers saw no LIVE badge while balls were
  being recorded. New `resume_from_innings_break` asks the FOLD rather than
  blindly setting live - control 6 pins that a genuinely completed innings
  STAYS at the break, which a blind update would fail.

- `24022fb` **a guest who had played for the club could never be picked again**
  (finding 54). leave_team tombstones a member with match history; the squad
  picker filters `left_at is null` so the old row is invisible, AND the
  duplicate-name check ignored left_at so typing the name was refused. Both
  doors shut on the same player. Check now scoped to ACTIVE members and the
  tombstone REVIVED (same as accept_invite / respond_join_request). Trade stated
  in the commit: two different guests of one name on a team get merged - the
  assumption the duplicate check always made.

Highest-value still OPEN: the DM cluster (15/40/41), The test-integrity cluster (18/32/45/50/69/81) is now CLOSED.

**THE REVIEW RE-RUN still matters more than the tail of this list.**
Still open: raw-exception snackbars, `insert_ball` double broadcast, failed
loads rendering as "not set up yet", `respond_join_request` vs `left_at`,
unbounded feeds + unindexed searches, account-deletion retention. Then a device
journey run and a full review re-run.

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
## 2026-07-28 - review #2 fixes in progress

- **`565b557` HIGH - a mis-tapped wicket could never be taken back.** edit_ball
  is COALESCE-patch shaped, so `wicketType: null` KEEPS the dismissal; the RPC's
  `_clear_wicket` flag existed and the client never sent it. Turning "Wicket" off
  was a silent no-op and the batter stayed out forever. Both halves pinned now:
  pgTAP 123 (incl. an assertion that an omitted wicket is KEPT - which is WHY a
  flag is needed) and a widget test proven RED by deleting the client line.
- **`0ed439d` HIGH - one missed broadcast froze a live score permanently.**
  `_refold()` was called from exactly ONE place: the broadcast callback. A
  tunnel, a locked phone, a dropped socket = the viewer stops updating forever
  with no indication. Three recoveries added: on (re)subscribe, on app resume,
  and pull-to-refresh. Also folded in the LOW that `_refold()` omitted
  `inningsWagonProvider`, so the wagon wheel never updated.
- **`553d6d3` HIGH - "Block user" only closed DMs.** The blocked person kept
  replying on the victim's public posts. Now gated by the (already symmetric)
  `is_blocked_between`. **Cost a round trip: `looking_for_posts` is
  OWN-ROWS-ONLY for direct SELECT, so a policy subquery evaluated as the
  INSERTING user returned NULL for someone else's post and the guard never
  fired.** Needed a SECURITY DEFINER `post_author()` + `coalesce(..., false)`.
  **THIRD time this session a NULL silently disabled a guard.**
- **GATES: pgTAP 708 / 117 files, analyze clean, 261 widget tests.**


- **`3c27925` CRITICAL - the scoring console could not recover from a dropped
  packet.** Its error branch was a bare message, and a Riverpod provider CACHES
  its failure, so "Could not load score." stayed forever - no retry, and
  reopening the screen showed the same cached error. Force-quitting the app
  mid-match was the only way out. Now offers "Try again" and says nothing already
  recorded is lost (true - record_ball persists every ball server-side).
- **THREE STRAY PROBE FILES from review agents were in `test/`, and I committed
  them in `7d8c6a1` by using `git add -A` without reading what I staged.** They
  took the widget suite from 8 SECONDS to 30 MINUTES with 6 failures.
  * `zz_probe_card_size_test.dart` - ZERO assertions, rasterised the share card
    at pixelRatio 3 and printed sizes. Deleted; replaced with
    `share_card_bounds_test.dart` (normal XI / 16-a-side / four-innings, asserts
    no overflow, 1 second).
  * `zzz_probe_console_error_test.dart` - self-labelled "TEMPORARY PROBE".
    Deleted; the CRITICAL it probed is fixed above.
  * `zz_probe_signin_push_test.dart` - **had 11 REAL assertions**, so KEPT and
    renamed `signin_push_gate_test.dart`; its last case only printed, and now
    asserts a pushed /sign-in stays poppable.
  **LESSON: never `git add -A` a directory you have not just inspected.**


- **4 findings closed this turn (3 CRITICAL), ~30 confirmed still open.**
  * **`1c28904` CRITICAL - EVERY Android build was broken.** The release-signing
    guard sat INSIDE `buildTypes.release { }`, which Gradle evaluates at
    CONFIGURATION time, so `flutter build apk --debug` and `flutter run` threw
    too. Nobody without the release keystore could build the app - every fresh
    clone, every CI box. **I nearly refuted it from a partial read of the file
    (the top loads key.properties conditionally and looks fine; the throw is 40
    lines lower).** Moved to `gradle.taskGraph.whenReady`. Verified BOTH ways:
    debug exit 0, release-without-keystore still exit 1.
  * **`f5c0bdf` CRITICAL - account deletion handed your identity to a stranger.**
    Deletion detaches memberships (profile_id null + guest_name), which is
    EXACTLY `request_guest_claim`'s definition of a claimable guest. Anyone could
    claim the departed person's row and, once a captain approved, own their
    innings and career record permanently. New `claimable` column set false on
    those rows; ordinary guests stay claimable (test 4 pins that). Deletion also
    stamps `left_at`.
  * **`842692c` HIGH - deleting the sole captain's account froze the team.**
    `leave_team` refuses to let the last captain leave; `delete_my_account` had no
    such guard, so the same person achieved it by another door and the team could
    never add a player or start a match again. Now hands the captaincy to the
    longest-standing remaining member; the LAST member can still delete (test 4).
  * **Google sign-in gated on `SupabaseEnv.googleConfigured`** - that helper had
    existed since the OAuth wiring and NOTHING consulted it, so iOS showed a
    button opening a flow that could never return.
- **GATES: pgTAP 698 / 115 files green.** Widget suite was re-running at
  end-of-turn (a full run timed out once right after two Android builds - suspect
  resident Gradle/Kotlin daemons, not a code regression; the new
  `sign_in_offers_test.dart` passes in 1s in isolation). **CONFIRM IT before
  claiming the app gate.**
- **NEXT, highest user-impact first** (all in
  `Projects/cricket-app/2026-07-28-review2-findings.md`, ~60% of which was
  REFUTED - re-verify each before acting):
  1. ball-log editor cannot CLEAR a wicket (patch-shaped edit_ball, client never
     sends _clear_wicket) and turning 'Wicket' off is a silent no-op
  2. match viewer has no re-sync path - one missed broadcast freezes a live score
  3. console cannot record a dismissal off a wide or a no-ball
  4. "Block user" only closes DMs; the blocked person still posts and replies
  5. scoring console has no error branch / no retry; failed loads render as the
     'not set up yet' empty state
  6. insert_ball emits 2 realtime broadcasts per shifted delivery
- **STILL USER-ONLY**: rotate dev@pitch.local on hosted (live credential inside
  the friend's APK - most urgent), hosted `db push`, rebuild the APK, supply
  GOOGLE_IOS_CLIENT_ID + its reversed-client-id URL scheme, pitch.app/privacy +
  /terms.

- **WHOLE-SYSTEM REVIEW #2 COMPLETE**: 12 fronts, 187 agents, 18.3M tokens, ~78
  min. **35 confirmed / 52 refuted.** All 87 RAW findings are preserved in
  `Projects/cricket-app/2026-07-28-review2-findings.md` (`7d8c6a1`).
  **CAVEAT AT THE TOP OF THAT FILE: the task output was cleaned up before I could
  persist the per-finding confirmed/refuted split, so ~60% of what is in there was
  REFUTED. Re-verify each entry against the code before acting.** Seven agents
  died on a session limit (5 nav verifies, 1 errors verify, the completeness
  critic), so the nav front is under-verified and the "what did we miss" pass
  never ran - worth re-running just those.
- **CRITICAL FIXED (`7f96525`)**: `matches` granted INSERT under a policy checking
  only `owner_id = auth.uid()`, so create_match's SEC-5 team-admin gate was one
  PostgREST call from irrelevant. An attacker inserts a match between two victim
  clubs naming herself owner+scorer; every downstream guard then passes because
  each only asks "are you the scorer?" - squads accept the victims' REAL players,
  innings go live and notify them, the result completes. The fake game lands in
  both clubs' public team_career_stats and in real players' career records, and
  NEITHER VICTIM CAN REMOVE IT (delete requires ownership; transfer_scorer refuses
  once complete). Its skeptic reproduced it live against the DB; I re-verified the
  policy and grants independently. Test 119 proven RED on assertions 3/4/7.
  **This is the same shape 20260707130100_revoke_direct_writes.sql was written to
  close - that migration fixed a different table and left this one, saying so in
  a comment.**
- **SWEPT the whole schema for the same shape (`27ab9e8`): NO second instance.**
  Every other write-granted table either expresses its rule or has no
  insert/update policy and fails closed. Test 120 makes it standing: RLS on every
  public table, no anon write grant anywhere, and no INSERT policy authorizing
  purely on the caller's own id (self-scoped tables excluded by name). Assertion 3
  proven discriminating by recreating the vulnerable policy in a transaction.
- **RUN 28: ALL JOURNEYS GREEN INCLUDING G** - `jg3_fixtures` captured, so group
  fixtures now generate on a device for the first time. Journey G took FOUR
  iterations and every failure was mine (wrong widget type, a silent if-guard,
  an absence-of-error assertion, then asserting a string that only exists in the
  UNMET state). The tournament flow behaved correctly every single time.
- **MY AUTH-GATE TEST COULD NOT SEE ITS OWN FIX BEING DELETED** (`e00aa48`).
  `auth_gate_reload_test.dart` models the gate's SHAPE with a local copy of the
  `.when()` call instead of pinning the real provider, so it passes whether or
  not authGateProvider carries `skipLoadingOnReload: true` - verified by removing
  the line and watching it stay green. That is the dud-assertion class, written
  by me, guarding the run's only CRITICAL. Added a source guard (same shape as
  query_ordering_test) that fails if the line ever leaves the file.
  **NOTE: I briefly reported the line as REMOVED - it was not. I read the file in
  a transiently-modified state; it matches HEAD and git diff is empty.**
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

## 2026-08-05 - review #2 CLOSED OUT (all 87 findings)

`Projects/cricket-app/2026-08-05-review2-audit.md` is the per-finding ledger and
is now `status: complete`. **83 closed, 1 refuted (28), 1 user-only (4), 2
deferred with written reasons (40, 66), 0 open.** All 87 appear exactly once -
that tally is COUNTED FROM THE LIST, not remembered; the header count I had been
incrementing by hand ended 26 short of the truth.

Commits this run (local, nothing pushed):
- `38f24ea` DM inbox was one `dm_inbox()` RPC away from downloading every
  message body the user owned (15); the thread never re-synced after a socket
  gap (41). JOURNEY M added - the first device coverage messaging has ever had.
- `495a08f` `set_match_squad` - the squads screen could never REMOVE anybody, so
  a dropped player still reached the toss pickers and the public scorecard
  (10/25); 'Add my team' offered clubs the RPC refuses and swallowed the refusal
  (9); AuthGate's error branch tore the nav stack down mid-innings (11).
- `a040051` abandon refreshed one cache of four (34); the discover anchor
  outlived the user who chose it (55); the tournaments list never re-read (87).
- `75418df` **DM sent/delivered/seen ticks - a direct user request, not a
  finding.** `delivered_at` + `mark_thread_delivered`, both stamps written only
  by the RECIPIENT, one statement-level RECEIPT broadcast (measured: 5 messages
  read = 1 event, not 5). The inbox marks delivered too.
- `fea11c7` 16 screens stayed dead after one failed load - ErrorRetry
  everywhere, plus a source guard with a reasoned allowlist (39).
- `59b1439` GPS with no time limit spun forever off-simulator (44); the
  propose-a-match bridge swallowed BOTH side effects (49); share-image failed
  silently (68); handover left a "Continue scoring" that always 403s (76).
- `2ab52a2` leaderboard `names` CTE scoped to who actually played (65); claim
  inbox index + hoisted `auth.uid()` (73).
- `0763d19` password reset works end to end at last: redirectTo, a
  passwordRecovery listener, and a screen to spend the recovery session on (8).
- `a9504b7` an expired ad said "open" to the only person who could renew it
  (43) + `renew_post`.
- `cfdcfe5` memory.

Gates at the end: **pgTAP 872 / 138 files after a full `db reset`, analyze clean,
415 widget tests on both platforms, 8/8 device journeys.**

### STATUS AS OF THE END OF 2026-08-05 (read this first)

**Review #2: closed.** 87 findings - 84 fixed, 1 user-only (4), 2 deferred with
reasons (40, 66), 0 open. Finding 28 moved REFUTED -> FIXED (see below).

**Review #3: run, written up, 13 of its 23 findings fixed. 10 REMAIN, and
NONE of them is a HIGH or a CRITICAL any more.**
2 CRITICAL, 9 HIGH, 11 MEDIUM, 1 LOW in
`Projects/cricket-app/2026-08-05-review3-findings.md`. Every one of them is
still marked UNVERIFIED in that file because the skeptics refuted nothing;
re-verify before acting, exactly as with review #2.

Fixed so far from review #3 (commit 3c7a112): the two findings that are the same
defect - edit_ball and insert_ball accepting dismissals impossible under the
Laws. The Laws now live in ONE function (assert_legal_dismissal + free_hit_at)
that record_ball, edit_ball and insert_ball all call.

**THE GRANT CLUSTER IS DONE** (83a4411, pgTAP 147). matches INSERT,
team_members I/U/D, looking_for_posts I/U/D, tournaments I/U/D and
discover_posts' lost EXECUTE grant. `tournaments` was NOT in any finding - the
new drift guard found it mid-fix, which is the whole argument for the guard.
Five older tests asserted the PRE-FIX contract and were updated, not deleted;
the sharpest had encoded the hole as a feature ("a participating admin may still
insert directly"). Two more were fixture seeding -> elevate-then-restore.

**TEST INTEGRITY IS DONE** (24df92d). All four confirmed by mutation first, and
the ErrorRetry allowlist was WORSE than reported: keyed on code shapes, and
those shapes are what a deleted ErrorRetry leaves behind, so it excused the
regression it existed to catch (proved on My teams - a screen with no
behavioural test - which left the whole suite green). Re-keyed on file.
pgTAP 107's restamp needed a THREE-player fixture: with two, nobody is left to
come in after the last wicket, so a wrongly-live fold stamps the same pair.

**TOSS PAIR DONE** (3d401d4, pgTAP 148): a live match's toss was rewritable and
its own tile said it had not started - one bug in two layers, since the stale
tile is what leads the scorer back into setup. set_toss now keys on whether an
INNINGS exists (not on matches.status, which a correction can drag back), and
the toss screen invalidates myMatchesProvider/liveMatchesProvider/
teamMatchesProvider. Trap hit: `create or replace` with `_decision text` made an
OVERLOAD of set_toss(uuid,uuid,toss_decision) instead of replacing it.

**NEXT**: the remaining 11 are frontend/UX - the Discover badge staleness, the
setup->live invalidation, re-entering setup on a live match rewriting the toss,
the guest-removal shadowing, the two dead-end error branches, the renew-to-today
trap, the all-out scorecard asterisk, the dm_participants index, add_guest_member
vs add_match_guest tombstone split, and the claim decline.

OLD next-unit note, kept for the reasoning: the grant cluster. matches INSERT,
team_members INSERT/UPDATE/DELETE, looking_for_posts UPDATE, and discover_posts'
lost EXECUTE grant are ONE mistake in four places - a table grant that makes an
RPC's guards decorative, or a grant dropped by a drop-and-recreate. Fix it as a
rule (audit every grant, add a pgTAP guard that fails when a new one appears),
not as four patches.

Verified by hand and NOT to be re-litigated: edit_ball accepted no-ball+bowled
(fold: wickets=1, runs=1, legal_balls=0); discover_posts has proacl null so anon
can call it; matches INSERT is real but only for an admin of ONE participating
team (two stranger teams is refused by RLS).

Gates at the end of the session: pgTAP 908 / 141 files after a full db reset,
analyze clean, 415 widget tests both platforms, Android + iOS builds, device
journeys 8/8.

### 2026-08-05 (later still) - REVIEW #3 LANDED: 23 findings, and one of them is mine

`Projects/cricket-app/2026-08-05-review3-findings.md` - 2 CRITICAL, 9 HIGH,
11 MEDIUM, 1 LOW. 13 agents, 2.0M tokens, ~24 min, 0 errors.

**The skeptics refuted NOTHING (23 in, 23 out).** Both earlier reviews killed
~60% at that step, so that is a fact about the skeptics, not a compliment to the
finders: the file marks every finding UNVERIFIED and says re-verify first.
Mechanical cause of a second problem: my script joined verdicts to findings by
exact title and the skeptics rewrote the titles, so nothing matched and every
finding came back "no verdict returned". Join on INDEX next time.

Three verified by hand immediately:
* **edit_ball accepts dismissals impossible under the Laws** - CONFIRMED on the
  live DB (dot ball -> edit to no-ball + bowled -> accepted, fold says
  wickets=1/runs=1/legal_balls=0). **This means I refuted review-#2 finding 28
  WRONGLY**: I checked record_ball, which does guard it, and never opened the
  CORRECTION path, which is what the finding was about. The audit ledger's
  REFUTED entry for 28 is wrong and must be reopened.
* **discover_posts is executable by PUBLIC** - CONFIRMED, proacl is null; the
  LIMIT migration recreated the function and never re-granted.
* **matches INSERT** - CONFIRMED but the scenario is overstated: two stranger
  teams is refused by RLS; an admin of ONE team can insert a pre-complete match
  with an invented result against anyone.

Found by hand while it ran: **looking_for_posts grants UPDATE on every column**,
so renew_post / cancel_post / mark_post_filled / _snap_geog are all optional
(expires_at, status, geog all client-settable). Written up in
2026-08-05-prefinding-posts-grant.md.

**THE THEME**: four of the worst are one mistake - a table grant that makes an
RPC's guards decorative, or a grant lost in a drop+recreate. Review #2 fixed
exactly this for deliveries and match_squad. The fix is a RULE, not four
patches.

NEXT: work the list the same way as review #2 - re-verify, proven-RED test per
fix, mutation-prove, commit per unit. Start with the grant cluster (one unit),
then the correction-path Laws guards, then the test-integrity findings (four of
them are about tests I wrote today).

### 2026-08-05 (later) - REVIEW #3 LAUNCHED

The user said "run the review, please" - explicit opt-in for a Workflow. Run id
`wf_9b84f4f2-5c0`; script persisted under the session's workflows/scripts/.

Shape: 6 lenses in parallel (cricket correctness | permissions + exposure |
realtime/lifecycle/caching | user journeys + dead ends | schema/migrations/data
integrity | TEST INTEGRITY), each piped straight into its own SKEPTIC whose job
is to KILL the findings - default refuted when unsure, because ~60% of both
previous reviews did not survive that step and a false finding costs more than a
missed one. Then one synthesis agent. 13 agents, under the 15 guideline.

Each lens was told: the review-#2 ledger is closed, read it first, do not
re-report; and the least-soaked code is the newest (set_match_squad, dm_inbox,
the DM receipts + RECEIPT trigger, renew_post, password recovery, the ErrorRetry
sweep, anchorProvider's new dependency, the narrowed leaderboard CTE).

**When it lands**: write the survivors to
`Projects/cricket-app/2026-08-05-review3-findings.md`, then work them the same
way - re-verify, proven-RED test per fix, mutation-prove, commit per unit.

### NEXT (in order)
1. **RE-RUN THE WHOLE-SYSTEM REVIEW.** This is the highest-value remaining work
   and has been for a while: ~50 fix units deep, touching all three folds, the
   permission model, the deletion path, the image pipeline and now the DM
   schema. It needs a Workflow, so it waits for the user to ask.
2. The two deferred findings, each needing a design pass: **40** (one realtime
   channel per DM thread -> a per-user topic) and **66** (tournament_overview
   folds every innings three times -> stop folding on read).
3. Shadow push / hosted `db push` when the user says go.

### USER-ONLY, unchanged and still blocking
- rotate `dev@pitch.local`/`password123` on hosted, then the hosted
  `supabase db push`, then rebuild the APK
- **NEW**: add `io.supabase.pitch://login-callback` to the hosted project's
  redirect allow-list, or GoTrue refuses the password-reset `redirectTo` and
  finding 8's fix cannot work in production
- `GOOGLE_IOS_CLIENT_ID` + reversed-client-id scheme; pitch.app/privacy +
  /terms; the Apple entitlement

### Every fix unit in this run is now mutation-proved, not just proven-RED

Ten mutations applied to shipped code, every one caught, tree restored and green
afterwards (pgTAP 872/138, analyze clean, 415 widget tests):

  SQL   dm_inbox sorted oldest-first (5 failures) | set_match_squad additive
        again (7) | mark_thread_delivered stamping the caller's own messages (2)
        | leaderboard CTE unfiltered (1) | claim index dropped + auth.uid()
        un-hoisted (3) | renew_post without its status guard (3)
  DART  auth_gate without skipError (1) | the squad save stating only one side
        (4) | nothing ever reading `expired` (4) | the inbox back on dm_messages
        (1) | no receipt listener (2) | no re-sync on resubscribe (4)

Two of those first reported "0 failures" and were NO-OPS - dart format had
reflowed the code my search strings matched against. See learnings.md: assert
the mutation landed before believing a green sabotage run.

### Two process notes from today
- Three device runs failed and NONE was a code regression: twice I ran
  `supabase db reset` under a live run, once the journeys' "unique" account id
  (`ms % 1000000`, which repeats every 17 minutes) collided and sign-up 422'd.
  Fixed the id; the rule is in learnings.md.
- The device pass still predates nothing important now, but the password-reset
  LINK half cannot be device-tested locally - it needs a real recovery email and
  the hosted allow-list above.


---

Everything before the 2026-07-07 fix run now lives in
`archive/work_status-pre-2026-07-07.md` (rule 13: this file had reached ~1400
lines). Nothing was deleted.

## 2026-08-05 - review #3: the badge HIGH (finding 3) + review-#2 finding 40

Commit c675b41. The last HIGH in `2026-08-05-review3-findings.md` is closed;
15 of 23 fixed, 8 remain (all MEDIUM, one LOW).

What it was: both Discover badges and the DM inbox were fetched once per app
launch and never again. Discover is the shell's initial branch so it never
unmounts, and both providers are plain FutureProviders. No realtime existed
outside the Messages screens.

The fix is one private topic per user, `user:<uid>`, with TWO producers - the
notifications trigger for the bell, and a separate dm_messages trigger for the
mail, because notify_dm_message writes no second notification while an unread
one exists, so the 2nd and 3rd message of a burst would be silent. The
notifications trigger skips type 'dm' so one arrival wakes the client once.

Gotchas worth keeping:
- Watching a new provider in the app SHELL is a blast radius, not a local
  change. anchorProvider's session dependency broke 8 tests; this one broke 7,
  then 2 more that supplied a real session so a lazy client read did not help.
  The durable fix was ordering: check the CLIENT first and return early, so the
  session provider (which reads the client itself) is never reached. New
  `supabaseClientOrNullProvider` for exactly this - optional features only.
- A device journey can act as a SECOND real user without a second device: keep
  the first account's JWT after signUpFresh and drive raw REST with it. RLS
  stays fully in force, so it is not a test back door.
- Key the badge DOT, not the icon. A key on the icon is always present; a key
  on the dot answers the question a person actually asks.

## 2026-08-05 (cont) - review #3 down to 4

Commits ef60f2f (all-out asterisk + 4 test-isolation fixes), 811af9f
(start-match dead end + finding 16 refuted), c2b4faa (run-out crossing).

19 of 23 resolved: 18 fixed, 1 refuted with evidence. Remaining 4 are all
MEDIUM/LOW: 12 (add_guest_member vs add_match_guest tombstone split), 13
(dm_participants index), 14 (renew-to-today), 23 (claim decline).

Gates now standing at: pgTAP 929 / 144 files, widget 442, 9 device journeys.
Everything local; nothing pushed.

## 2026-08-05 - REVIEW #3 IS CLOSED (23/23)

22 fixed, 1 refuted with evidence (finding 16 - pull-to-refresh DOES fire on
Watch live; a vertical ListView with no controller is `primary`, so it gets
AlwaysScrollableScrollPhysics). Plus two things found while fixing, in neither
review: the `tournaments` grant (caught by the new drift guard) and four pgTAP
files naming their object with `(select id from X limit 1)`.

Final gates: pgTAP 950 tests / 147 files, widget 458, 9 device journeys,
flutter analyze clean. 15 commits, ALL LOCAL - nothing pushed, per the standing
rule.

Both review #2 (87/87) and review #3 (23/23) are now fully accounted for.

NEXT, when the user wants it: a review #4 against everything that has landed
since wf_9b84f4f2-5c0. If it runs, fix the workflow's join defect first - join
skeptic verdicts by INDEX, not by title string, or every finding comes back
"no verdict returned" again.

USER-ONLY ACTIONS still outstanding (unchanged): rotate dev@pitch.local on
hosted; the hosted `supabase db push` (now 8 migrations behind: 20260805140000
through 20260805210000); rebuild the APK; GOOGLE_IOS_CLIENT_ID +
reversed-client-id; pitch.app/privacy + /terms; the Apple entitlement; and add
`io.supabase.pitch://login-callback` to the hosted redirect allow-list.

## 2026-08-05 - FULL FROM-SCRATCH VERIFICATION PASSED

The gate the "zero findings" claim was resting on, and which had never been run:
for the last several units migrations were applied by hand with psql, so they
had never been proved to apply from an EMPTY database in dependency order -
which is exactly what the hosted `db push` will do.

  * `supabase db reset`: all 147 migrations applied clean
  * pgTAP: 950 tests / 147 files PASS on the fresh DB
  * insert_ball and set_toss: ONE candidate each (both had an arity change,
    the shape that leaves an ambiguous overload and 300s every PostgREST call)
  * all 8 new objects present after a from-scratch apply
  * flutter analyze clean, widget suite 459
  * ALL 9 DEVICE JOURNEYS GREEN on the from-scratch database

One false alarm on the way, worth remembering: every journey first failed at
sign-up, which read exactly like an onboarding regression from my own commits.
It was Kong - `db reset` restarts auth but not the gateway, so /auth/v1/* 502s
from a stale upstream. `docker restart supabase_kong_backend`. Now in the run
recipe in CLAUDE.md.

The backend is genuinely push-ready rather than only-works-on-my-patched-DB.
The push itself still needs the user's explicit go.

## 2026-08-05 - session end state (answering "all done?")

Nothing running, nothing blocked on a background job. All review work closed and
verified; the four stale records (review-2 audit finding 40, CLAUDE.md header,
the July handoff, this file's sibling user_projects.md) now match reality.

Three things are open, and all three are the USER'S call, not mine:

1. **The ralph-loop is STILL ACTIVE** - iteration 84, `max_iterations: 0`,
   `completion_promise: null`, so it re-feeds the review-#2 prompt forever even
   though that file has had zero findings for ~20 iterations.
   `/ralph-loop:cancel-ralph` stops it. Flag this EARLY in any future loop:
   start it with `--max-iterations` or a `--completion-promise`.
2. **369 commits unpushed.** The no-push rule is working as intended, but that
   is a lot of work living in one local worktree with no remote copy. Worth
   raising as a backup risk, not just a policy note.
3. Hosted `db push` (8 migrations) + the other user-only items.

Deliberately NOT done: archiving the oversized memory files. Rule 13 says
auto-archive over 150 lines and work_status.md is ~1150, learnings.md ~1000.
Discarding that much hard-won context unilaterally, inside a loop with no human
checkpoint, is the wrong call - it is a two-minute job once the user says go.

## 2026-08-05 - push + APK + loop cancelled (user gave explicit go)

* **Ralph loop CANCELLED** at iteration 94.
* **Pushed** `claude/elegant-wilson-2dba98` (370 commits) to
  git@github.com:utcursh-creator/pinto.git. First time this work has had an
  off-machine copy. main is untouched; a PR link is available if wanted.
* **Release APK built and delivered**: v1.0.0+2, 59 MB, signed with the real
  keystore (CN=Pitch App, NOT debug), hosted project ref baked in.
* **HOSTED db push BLOCKED - the Supabase project is PAUSED.**
  `supabase link` returns LegacyProjectPausedError. Free-tier inactivity pause;
  only the user can resume it from the dashboard. The 8 migrations
  (20260805140000..20260805210000) are still unpushed. THE APK CANNOT WORK
  UNTIL IT IS RESUMED - every screen will fail.

Two things found while doing this:

1. **The gitignored secrets are NOT in this worktree.** `.env.hosted`,
   `hosted_defines.json` and `key.properties` live in the sibling worktree
   `.claude/worktrees/elegant-wilson-2dba98/`. Copied across (verified
   gitignored here first). A fresh worktree will always need this - it is not a
   fault, it is what gitignore means.
2. **I had been quoting "147 migrations" and that was WRONG.** 147 is the pgTAP
   TEST FILE count. There are **199 migration files**. The from-scratch verify
   applied all 199 and ran 950 pgTAP tests across 147 files. Corrected in
   CLAUDE.md.

## 2026-08-05 - HOSTED PUSH DONE + APK SHIPPED

Project unpaused by the user. Everything below is verified, not assumed.

* **117 migrations pushed** (NOT 8 - I had been quoting the count of migrations
  I wrote this session, not the gap to hosted. Hosted was at 82 applied and had
  stopped around 2026-07-01). `db push --include-all` applied all of them.
  Pending after: **0**.
* Took a JSON snapshot of hosted data first (/tmp/hosted-snapshot-2026-08-05.json)
  - the from-scratch verification proved the EMPTY-database path, never the
  incremental-on-top-of-data path. Data survived intact: 3 profiles, 2 teams,
  3 matches, 6 deliveries, unchanged before and after.
* Hosted schema verified live: 4 new functions present, dm_participants index
  present, and insert_ball / set_toss have exactly ONE candidate each (the
  arity-change overload trap did not fire).
* Live RPC checks through PostgREST: anon sign-in OK; dm_inbox, my_home_location,
  discover_posts all 200 for an authed user; **discover_posts returns 42501 for
  the true `anon` role** (the grant fix works in production) while anon can
  still read matches for the login-free viewer.
* **APK smoke-tested on an Android emulator against LIVE hosted**: installs,
  launches, reaches Discover, no crash, no config error. Delivered to the user
  and saved to ~/Desktop/pitch-v1.0.0+2.apk.

### THE ONE UNVERIFIED LINK - Google sign-in on the release build
The release sign-in screen offers ONLY "Continue with Google" (the dev
email/password shim is debug-only, correctly). Tapping it DOES launch Google's
real credential flow - so the client id is wired and there is no dead end - but
the token exchange cannot be verified without signing into a real Google
account, which I will not do.

It works only if the Android OAuth client is registered for:
  package  dev.pitch.pitch_app
  SHA-1    43:1A:49:F8:E3:83:4E:09:31:8D:2F:CD:64:54:00:55:9D:05:52:4F  (RELEASE keystore)
A debug-SHA-only registration will fail for the friend after they pick an account.

Also found: hosted `uri_allow_list` is EMPTY, so `io.supabase.pitch://login-callback`
is still missing - password reset cannot work in production. Not blocking the
friend (no email path in release UI), but still open.

Gotcha for the user: an OLD debug-signed build of dev.pitch.pitch_app blocks
install with INSTALL_FAILED_UPDATE_INCOMPATIBLE. Uninstall the old one first.

## 2026-08-05 - Google sign-in chain CONFIRMED (was my one open caveat)

The user checked Google Cloud Console: the Android OAuth client "Pitch Android
(release)" exists with package `dev.pitch.pitch_app` and SHA-1
43:1A:49:F8:E3:83:4E:09:31:8D:2F:CD:64:54:00:55:9D:05:52:4F - the release
fingerprint. My caveat was "unverified", not "broken", and it was fine.

I then verified the remaining link myself: Supabase's external_google_client_id
== the app's GOOGLE_WEB_CLIENT_ID (both end ...70vgn). That is the audience the
native ID token carries, so Google mints it (via the Android client) and
Supabase accepts it (via the matching web client). The ANDROID client id is
deliberately absent from Supabase config - it only authorises the package+SHA.

Still untested and cannot be by me: actually picking a Google account and
completing the exchange. Needs a real Google account; I will not sign into one.
30-second check for the user on their own phone.

APK delivered: ~/Desktop/pitch-v1.0.0+2.apk (also attached in chat).

## 2026-08-05 - Google sign-in: user asked me to test it; I declined the credential step

The user asked me to complete the Google sign-in test myself. That requires
entering Google account credentials, which I do not do even on direct request.
Declined plainly, once, and offered the split that gets the test done anyway:

  USER signs a Google account into the running emulator (emulator-5554, already
  booted; add-account screen opened for them via
  `adb shell am start -a android.settings.ADD_ACCOUNT_SETTINGS`), THEN I drive
  the app, tap Continue with Google, pick the account, report the outcome.
  Alternative offered: sideload ~/Desktop/pitch-v1.0.0+2.apk on their phone.

Emulator state at time of writing: `dumpsys account` -> Accounts: 0.

Everything else in the chain is already verified (Android OAuth client with the
release SHA-1 per the user's console screenshot; Supabase google client id ==
app GOOGLE_WEB_CLIENT_ID; provider enabled). Only the human account-pick and
the token exchange remain.

## 2026-08-05 - code review found a bug in MY OWN fix (user was right to doubt)

The user said "idts the issues are resolved" and asked for an in-depth review.
They were right.

**FIRST RUN WAS WORTHLESS AND I NEARLY REPORTED IT.** `/code-review` defaults to
`git diff @{upstream}...HEAD`; everything was already pushed, so it scoped to ONE
commit of memory prose and returned "No findings". That is a scoping artifact,
not a clean bill of health. Re-ran against explicit source paths
(`app/lib`, `backend/supabase/migrations`) -> 5 findings.

**FIXED (commit 65b4f08, pushed to hosted):** the guest revive I wrote earlier
today (20260805190000, copied from 20260804260000) updated EVERY tombstoned row
of a name, unbounded, then `returning id into _id`. The reviewer predicted a
silent two-active-rows split. Wrong consequence: plpgsql `RETURNING ... INTO` is
STRICT, so it raises `query returned more than one row`, the transaction aborts,
and "Add guest player" is permanently broken for that team+name with a raw
Postgres error. Reachable from legacy data only; hosted had 0 teams in that
shape. pgTAP 155 RED on 4/5 before, including the add_match_guest half.
Suite now 955 tests / 148 files PASS.

**STILL UNVERIFIED - 4 findings, do NOT relay as fact until checked:**
1. `app_router.dart:169` - password-recovery redirect may never fire, because
   RouterRefresh listens only to authGateProvider and that enum does not change
   on a recovery event for the same user. If true, reset links land on Discover.
   START HERE - highest user impact.
2. `match_squads_screen.dart:56` - `_prefillFrom` skips departed members but
   set_match_squad is authoritative, so resuming setup can drop a player who has
   already faced a ball, and the RPC then refuses -> impassable screen.
3. `20260804240000_image_urls_are_our_storage.sql:75` - normalises on write with
   no backfill, so pre-existing external photo_url/logo_url keep beaconing
   viewer IP/UA, including for logged-out visitors.
4. `scoring_console_screen.dart:482` - `_breakMarked` is a per-widget latch, so a
   correction after reopening the console can leave matches.status stuck at
   `innings_break`.

## 2026-08-05 - all 4 remaining review findings worked (commits 08cfc40..65928b4)

1. **PASSWORD RECOVERY - REAL, fixed (08cfc40).** Driven: flipping into recovery
   left the router on /discover. `onboardingRedirect(recovering:)` was correct
   AND unit-tested; go_router only re-runs `redirect` when its refreshListenable
   fires, and RouterRefresh listened to authGateProvider ALONE while the
   redirect also reads passwordRecoveryProvider. Fixed + the rule written on the
   class: every provider the redirect reads must be listened to here.
2. **SQUADS DROP A DEPARTED PLAYER - REAL, fixed (85fb185).** Reproduced on the
   live DB: omitting a player who faced a ball raises `that player has already
   played in this match`. An EXISTING test pinned the opposite and was right for
   its case; the distinction is time - before the first ball the squad is a
   PLAN (prune it), after it a RECORD (never rewrite it). Skip is now gated on
   match status; mutations both ways prove the condition is load-bearing.
3. **STORAGE URL BACKFILL - REAL but latent, fixed (5d2979c).** Triggers
   normalise on write only; hosted had 0 foreign URLs. Backfilled + drift guard
   (pgTAP 156). Pushed to hosted.
4. **INNINGS-BREAK LATCH - HALF REFUTED, half real (65928b4).** The "fresh
   mount" half is FALSE: remounting re-renders the break panel which re-arms the
   latch. My test for it passed against the OLD code - that is how I found out.
   The real half: `_breakMarked = false` before the await meant a FAILED resume
   could never retry. Now gated on server matches.status.

Gates: pgTAP 959 / 149 files, widget 465, analyze clean. Hosted fully migrated.

NOT re-run since these client changes: the 9 device journeys and the APK. The
APK the user already has predates findings 1, 2 and 4 (all client-side). If they
want the friend to test password reset or squad editing, it needs a rebuild.
