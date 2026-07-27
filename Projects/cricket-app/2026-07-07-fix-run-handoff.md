---
type: handoff
date: 2026-07-07
project: cricket-app
status: active
tags: [resume, fix-run, penetration-review, pitch]
---

# RESUME HERE - Pitch fix run (post-compaction handoff)

**Read this FIRST after any compaction, then `Projects/cricket-app/CLAUDE.md`.**
This file is the single source of truth for the state of the current work. It is
written to be self-contained: everything needed to continue without the
conversation.

---

## 1. What the user asked for (standing instruction, still in force)

Verbatim intent, repeated and escalated several times:

> Fix EVERYTHING. Don't stop. Use the iOS simulator and use the app completely as
> a user would - while they're having a tournament, while they want to search for
> a team to play with, while they want to search for other players. Adding
> players and all of that must be done and verified BY YOU. Once done, run code
> review AGAIN - I'm 100% sure you'll find more defects - fix them, and run it
> again, repeatedly, until there are ZERO errors and the app works 100%
> end-to-end in production. Don't worry about token usage.

Also: **"look for MORE use cases / more user journeys"** - the three journeys
built so far are not the full set (see §7 for the backlog).

Running mode: **`/loop` dynamic mode**. Each turn ends with `ScheduleWakeup` so
the work continues without the user prompting. Do not end a turn without either
re-arming the loop or being explicitly told to stop.

### Non-negotiable standing rules (from `Projects/cricket-app/CLAUDE.md`)
1. No vibe coding - spec -> plan -> TDD -> verify.
2. OSS / pre-built first.
3. Backend before frontend.
4. **NEVER use em dashes** - hyphens only.
5. Verify external/library claims against current docs (Workflow), not memory.
6. Honest calibration. The user pushes back hard; that is good.

### Verification protocol - "verified" means ALL of
1. `flutter analyze` clean.
2. Widget tests pass on **both** platforms.
3. **Actually run on the iOS simulator and LOOK at the screenshot.**
4. Live backend round-trip.
5. Commit per unit, LOCAL only (never push/PR without explicit go).

---

## 2. Where the work came from

`Projects/cricket-app/2026-07-07-penetration-review.md` (390KB, commit `fe67959`)
- **100 confirmed findings**: 2 critical, 22 high, 36 medium, 40 low.
- Method: 12 adversarial attack fronts, each finding then handed to an
  independent skeptic told to REFUTE it. Run twice and merged (52 agents), plus a
  completeness critic that found a CRITICAL all 12 fronts missed.
- The synthesis section in that doc has the release gate, root-cause themes and
  a dependency-ordered fix plan. **Machine-readable copy: `/tmp/pitch_merged_findings.json`**
  (regenerate from the two task outputs if /tmp is cleared - see the doc).

---

## 3. Current verified state (as of this handoff)

```
Backend : 159 migrations, 104 pgTAP files, 621 tests   -> ALL PASS
App     : flutter analyze clean, 198 widget tests      -> ALL PASS
Device  : all 3 user journeys PASS on the iPhone 17 sim (run 7: "+4 All tests
          passed", 0 setState crashes, 0 failures, 11 screenshots)
Commits : 26 in this fix run (eacdd23 .. 2b86201), working tree clean
Branch  : claude/elegant-wilson-2dba98, worktree
          /Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e
```

### Gate commands (copy-paste)
```bash
export PATH="$HOME/development/flutter/bin:/opt/homebrew/bin:$PATH"; export LANG=en_US.UTF-8
cd Projects/cricket-app/backend && supabase db reset && supabase test db   # 621/104
cd ../app && flutter analyze && flutter test                                # 198
# device journeys (local Supabase must be up):
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/user_journeys_test.dart \
  -d 23708F23-B0FA-48AC-97B2-69330802D156      # screenshots -> /tmp/pitch_shots
```

---

## 4. FIX UNITS - what is DONE

| unit | commit | what |
|---|---|---|
| 1 | `eacdd23` | Both CRITICALs |
| - | `fba6e1a` | **Fold lockstep** (the data-corruption one) |
| 2a | `c88f1ff` | "RPC holds the rule, table is granted" - 5 holes |
| 2b | `b8508dc` | edit_ball data destruction, retirement-as-ball, delete_my_account |
| 2c | `5c27f0e` | discover location oracle, unfinishable innings |
| 3a | `082229c` | console: no-ball enum 400, dead Undo, shipped credentials |
| 3b | `be91902` | DM realtime registry, ball-log truth, resumable squad setup |
| 4a | `d3e333f` | shadcn-pattern primitives + `humanError()` across 32 files |
| 4b | `c6b3a68` | swallowed writes, no-team dead end |
| 4c | `aa484d1` | anon dead ends, permanent DM spinner, dead share link |
| 5a | `73733bb` | restamp broadcast storm, tied-knockout brick |
| 5b | `37bfe69` | tournament invite multi-use |
| 6a | `82e52d8` | release config that would ship broken |
| 7a | `114002b` | 12 pgTAP files rescoped off unscoped `limit 1` |
| - | `067adc3` | **Discover build-phase crash** (3 attempts, see §6) |
| - | `36fa9d5` | tournament 4-team minimum stated, not discovered |

### The two CRITICALs, for context
1. **Total team takeover.** `team_members` UPDATE policy had a
   `profile_id = auth.uid()` self-branch in its `WITH CHECK`, evaluated against
   the NEW row - so `team_id` and `role` were free. One PATCH made any user admin
   of any team; `is_team_admin` reads that same table so the forged row was
   instantly authoritative. Fixed: self-branch deleted, immutability trigger on
   `team_id`/`profile_id`, admin-gated `set_team_member_role` RPC with the
   last-captain guard server-side.
2. **Invite-built tournaments could never start** (found by the completeness
   critic, missed by all 12 fronts). `join_tournament_with_token` defaults teams
   to group 'A'; the organizer's group chips called `add_tournament_team`, which
   carries the SEC-8 `is_team_admin` consent gate the organizer cannot satisfy
   for an invited club - so every tap raised and was swallowed. With
   `canGenerate` needing >=2 in BOTH groups, fixtures were unreachable. Fixed by
   separating PLACEMENT (new organizer-gated `set_tournament_team_group`) from
   ENTRY.

---

## 5. WHAT IS LEFT - the actual TODO

### 5a. Remaining MEDIUM findings
- `discover-posts-never-expire`: `expires_at` is never written by any client and
  `discover_posts` has no match-date floor, so dead posts accumulate forever and
  outrank fresh ones. Fix: default `expires_at` server-side
  (`coalesce(_expires_at, _match_at + 1 day, now() + 14 days)`), add
  `and (p.match_at is null or p.match_at >= now() - interval '6 hours')`, and put
  recency in the ORDER BY.
- `team-member-delete-fk-restrict`: "Leave this team" / "Remove this player" can
  never succeed for anyone who appeared in a match squad - unhandled FK RESTRICT,
  raw Postgres error shown. Fix: `left_at timestamptz` soft-departure + a
  `leave_team(_membership_id)` RPC that hard-deletes only when no `match_squad`
  row exists, else stamps `left_at`; filter `left_at is null` in the roster
  provider and squad pickers.
- `notifications-dead-taps`: `claim_request` / `join_request` notification rows
  are tappable and do nothing.
- `public-deeplink-strands-outside-shell`: cold-starting a public deep link
  leaves the user on a single top-level screen with no way into the app.
- `team-invite-link-unreachable`: the shared invite link resolves nowhere and
  `/invite/:token` has no in-app entry point. Add a "Have an invite code?" entry
  and share the raw token.
- `signin-push-destroys-invite-and-join-stack`: signing in from an invite or
  tournament-join link destroys the link.

### 5b. Remaining LOW findings
iOS Apple sign-in entitlement + URL scheme registration; iPad
`sharePositionOrigin` on every SharePlus call; `edit_ball`/`insert_ball` PUBLIC
revoke; `did_not_bat` includes a dismissed batter; duplicate `GlobalKey`; storage
bucket enumeration; `retire_batter` guard asymmetry; tournament token row lock
(done in 5b) ; `create-profile-no-escape` (no sign-out escape if the profile
insert keeps failing).

### 5c. SHADOW PUSH (do before telling the user the push is safe)
Reset a local DB to the hosted **2026-06-27** schema, populate it like the
friend's data, then apply all **77 pending migrations** and confirm none abort.
The review found no migration that aborts, but that is inference, not evidence.

### 5d. Re-run the full review, repeatedly
Re-run the 12-front adversarial Workflow (the script is saved under the session
workflows dir; the prompt structure is in the review doc). Fix what it finds.
Repeat until it returns zero. **The user is certain more defects exist and has
been right every time so far.**

---

## 6. HARD-WON GOTCHAS (do not re-learn these)

- **THE RIVERPOD INVARIANT**: a **synchronous** provider must never watch an
  **asynchronous** provider. `Provider<int>((ref) => ref.watch(fp).value ...)` and
  `Notifier.build() => ref.watch(fp)` are the same bug. When a widget's first
  watch happens during build, that watch flushes the async ancestor inside
  itself; the ancestor yields a value, notifies the sync dependent, and the
  dependent calls `invalidateSelf` -> `scheduleRefresh` -> `setState` on the
  ProviderScope MID-BUILD. **Widgets MAY watch async providers; intermediate SYNC
  providers may NOT.** Fix = delete the intermediate provider, make the
  derivation a pure function the widget calls.
  This crashed Discover on EVERY open and took **three attempts** because there
  were three instances (`anchorProvider`, `unreadNotificationsCountProvider`,
  `dmUnreadCountProvider`).
- **When a crash MOVES to a new line after your fix, you fixed an instance, not
  the class.** On the second move, stop and `grep -rn "ref.watch(.*Provider).value" lib`
  before touching anything.
- **analyze + widget tests passed for ALL THREE broken attempts.** The unit layer
  cannot see this class of bug. Always re-verify on device.
- **Read the screenshots, not the exit code.** A green run still had a dead end
  in it (the tournament 4-team minimum).
- **`flutter build ios` error 74**: delete `build/ios`. Stale dir + the
  `com.apple.provenance` xattr that files under `.claude/worktrees/` carry. A
  direct `xcodebuild ... -sdk iphonesimulator build` succeeding proves the app
  code is fine.
- **`integration_test` runs every test in ONE app process and supabase_flutter
  PERSISTS the session** - later journeys start signed in. Call the
  `ensureSignedOut` helper first.
- **pgTAP**: psql does not interpolate `:'var'` inside `$$`-quoting - that is why
  the suite was full of `(select id from public.X limit 1)`. Use
  `format($$ ... %L ... $$, :'var')`. Unscoped, guard tests catch the WRONG error
  (RLS 42501 / 'not authorized' instead of the constraint) and pass for the wrong
  reason.
- **To prove a test-scoping fix, seed a decoy row** the unscoped query would have
  picked, then re-run. Passing on a clean DB proves nothing.
- **`create or replace function` with a different arity CREATES AN OVERLOAD.**
  Two candidates make calls ambiguous and PostgREST 300s. `drop function <exact
  old signature>` first.
- **pgTAP fixture writes that clients no longer hold** need `reset role;` then
  re-`authenticate_as`. Inside a plpgsql helper that will not work - define the
  privileged helper BEFORE `authenticate_as` so its definer is the session owner.
- **`tournament_invites` is organizer-only readable** - read it as the organizer.
- **A widget test reaching a button via `ensureVisible` can be passing by a
  one-line margin**: in a lazily-built ListView the off-screen child is never
  instantiated and it throws "Bad state: No element". Use `scrollUntilVisible`.
- **UI labels verified against source** (I guessed all three wrong once): create
  team button = **'Create'**; guest CTA = **'Add guest player'**; tournament
  submit = **'Create tournament'**.

---

## 7. MORE USER JOURNEYS TO BUILD (the user explicitly asked for these)

`app/integration_test/user_journeys_test.dart` currently covers three. The user
wants the full realistic set. Candidates, highest value first:

1. **Score a full match end-to-end through the console** - toss, openers, all
   extras (wide+runs, no-ball+byes - the enum bug lived here), a wicket with the
   incoming batter, retire a batter, swap strike, undo across an over boundary,
   innings break, chase, result, then the scorecard. (`rebuild_gate_test.dart`
   covers part of this; extend rather than duplicate.)
2. **Correct a scored match** via the ball log - edit a ball, insert a missed
   ball, delete one - and assert penalty runs / wagon shot / crossed survive
   (Unit 2b made `edit_ball` a patch).
3. **Two-device live watching** - scorer records, a second client sees it push
   (`live_push_test.dart` exists; fold it into the journey set).
4. **A full tournament to a champion** - 4 teams, groups, fixtures, score them
   all, generate playoffs, a TIED semifinal broken via `resolve_tied_fixture`,
   then the final and the champion banner.
5. **Join a team by invite link** as a second user, and the captain approving a
   join request.
6. **Guest claim** - "This is me" on a guest row, captain approves from the claim
   inbox, career stats follow the claim.
7. **Account deletion** - delete an account that has match history and assert the
   opponent's scorecard still renders under "Deleted user".
8. **Anonymous browsing** - watch a live match and view a public tournament with
   no account, and confirm every gated action offers sign-in rather than an error.

---

## 8. ONLY THE USER CAN DO THESE (do not attempt)

1. **Rotate / delete `dev@pitch.local` and `other@pitch.local` on the hosted
   project and disable the email/password provider.** These are REAL credentials
   for a REAL account on production and they shipped inside the release APK the
   friend is holding. The prefill is now `kDebugMode`-only, but the account is
   still live. **Most time-sensitive item in the project.**
2. **Run the hosted `supabase db push`** (77 pending migrations). Classifier-
   blocked for me; needs their explicit go. In `Projects/cricket-app/backend`
   with `.env.hosted` sourced. Until then the friend's APK talks to a June-27
   schema.
3. **Rebuild the release APK after that push** (the app calls RPCs that do not
   exist on the old hosted schema).
4. Store prerequisites: `pitch.app/privacy` + `/terms` must EXIST (Settings links
   to them); Apple Developer + Play Console accounts; iOS Google client +
   reversed-client-id; deep-link domain registration.
