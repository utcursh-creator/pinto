# Whole-system review #2 - all raw findings

Run `wf_f990aa01-feb`: 12 fronts (sql, rls, cricket, state, nav, errors, realtime,
lifecycle, scale, platform, tests, privacy), 187 agents, 18.3M tokens, ~78 min.
Every finding faced TWO skeptics with different lenses (claim accuracy,
reachability) and was counted CONFIRMED only if NEITHER could refute it.

**The workflow reported 35 confirmed / 52 refuted.** The task output file was
cleaned up before I could persist the per-finding split, so what follows is the
complete set of 87 RAW findings reconstructed from journal.jsonl. Roughly 60%
were refuted - **re-verify each one against the code before acting on it.**
Seven agents died on a session limit (five nav verifies, one errors verify, the
completeness critic), so the nav front is under-verified.

The CRITICAL at the top was reproduced LIVE against the running database by its
skeptic, including a control proving RLS was genuinely enforced in that session.

---

## 1. [CRITICAL] Account deletion leaves the person's membership on every roster as a CLAIMABLE guest, so a stranger can inherit their whole career history (and their captaincy)
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260707130500_delete_account_always_anonymize.sql`:40

**Failure scenario**

Priya has played 30 matches for Mumbai United and is a captain there. She taps Settings > Delete account. `delete_my_account` runs `update team_members set profile_id = null, guest_name = coalesce(guest_name,'Deleted user') where profile_id = _me` and does NOT set `left_at`. Her row is now indistinguishable from a guest row that is still on the roster: `teamRosterProvider` (app/lib/src/features/identity/data/identity_providers.dart:65) filters only `left_at is null`, so she stays listed, and team_page_screen.dart:146 offers 'This is me' on every row with `profile_id == null` to any signed-in user. Rahul (any authenticated user, no relationship to the team) taps it; `request_guest_claim` accepts it because the row is now `guest_name is not null and profile_id is null`. The claim lands in the captain inbox as 'Rahul says they are Deleted user - review the claim' (claimInboxProvider selects only guest_name/team, never the row's role). Another admin approves. `approve_guest_claim` sets `profile_id = Rahul` on that same team_members row and leaves `role` untouched. Because v_player_key is `coalesce(tm.profile_id, tm.id)` and re-keys history at READ time (20260623141000_player_views.sql:13-17), Priya's entire batting/bowling/fielding record for that team is now attributed to Rahul on his public /player/:id page - and since the row's role was 'captain', `is_team_admin` now returns true for Rahul, handing him the team.

**Why it is real**

Verified in code, not inferred: the update at line 40-43 never writes left_at; the roster query and the claim button gate purely on left_at/profile_id; request_guest_claim's only precondition is guest_name non-null + profile_id null; approve_guest_claim updates profile_id and guest_name only, never role; the player-key view comment states outright that a claim re-keys the guest's entire history to the claimer with zero backfill. leave_team (20260707180000) sets left_at precisely so a departed person is off the roster - account deletion, which is a stronger departure, does not.

---

## 2. [CRITICAL] Release-signing guard throws at Gradle CONFIGURATION time, so every Android build fails - including debug
- **file**: `Projects/cricket-app/app/android/app/build.gradle.kts`:60

**Failure scenario**

`android/key.properties` is gitignored (android/.gitignore) and does not exist in this checkout. The guard lives inside `buildTypes { release { ... } }`, which AGP evaluates while configuring the project, not when the release variant is assembled. I ran the cached Gradle against this project: `gradle --offline -q help` in Projects/cricket-app/app/android fails with `* Where: .../android/app/build.gradle.kts line: 60` / `android/key.properties is missing - refusing to build an unsigned/debug-signed release.` `help` touches no variant at all, so `flutter run -d <android device>`, `flutter build apk --debug`, `flutter build appbundle`, `flutter drive` on Android and any CI Android job all die at configuration on a machine that has no release keystore. Android is currently unbuildable in a fresh clone.

**Why it is real**

Empirically reproduced, not inferred: the failing task was `help`, which requests no variant. The previous fix run replaced a debug-key fallback with `throw GradleException(...)` placed inside the release build type body; the intent (fail the RELEASE build) requires the check to run in a release-only task/`gradle.taskGraph.whenReady`/`androidComponents.onVariants`, not in the DSL block. The file's own header comment (lines 10-12) still claims `flutter build apk` works without secrets present, which is now false for every variant.

---

## 3. [CRITICAL] Scoring console's innings-state error branch has no retry, and the cached error makes it terminal for the whole app session
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:385

**Failure scenario**

A scorer opens Live scoring at a ground with a momentary signal drop (or a blip mid-innings while `_afterBall` at line 43 re-reads the fold). `compute_innings_state` fails, so `inningsStateProvider(inningsId)` settles into AsyncError and `state.when(error:)` replaces the ENTIRE body with `Center(Text('Could not load score.'))` - no Retry button, no pull-to-refresh, no run pad, no bowler picker, and `_betweenBallRow` (Undo/Swap/Retire) is inside the `data:` branch so it is gone too. `inningsStateProvider` (match_providers.dart:120) is a plain `FutureProvider.family`, i.e. NOT autoDispose (riverpod 3.3.2 defaults `isAutoDispose = false`), so the error is cached for the life of the ProviderContainer: popping the console and re-entering from Matches -> 'Continue scoring' re-watches the same element and gets the same cached error instantly, without ever re-hitting the network. The scorer cannot record another ball for the rest of the app session; the match sits half-scored until they discover that force-quitting the app is the fix. (The only in-app escape is the app-bar Ball log, deleting or editing a real ball, which happens to call `ref.invalidate(inningsStateProvider(...))` - no user will find that.)

**Why it is real**

Every other async surface that the previous reviews touched got a retry affordance (ErrorRetry in discover_screen.dart:121 / profile_screen.dart:24, `_CenteredMessage(onRetry:)` in match_viewer_screen.dart:323, live_matches_screen.dart wraps `when` in a RefreshIndicator so even its error branch is refreshable). The console - the highest-stakes write surface in the app - was left with a bare Text. The codebase already documents the exact caching mechanic that makes it permanent: match_providers.dart:19-22 explains that a non-autoDispose family "stays cached as a failure, so retyping the same name never retries", and that fix was applied only to `opponentSearchProvider` (the single `.autoDispose` in the entire lib/, verified by grep).

---

## 4. [CRITICAL] iOS Info.plist has no Google reversed-client-ID URL scheme - tapping "Continue with Google" raises an uncaught NSException and kills the app
- **file**: `Projects/cricket-app/app/ios/Runner/Info.plist`:62

**Failure scenario**

On a real iOS build configured with `--dart-define GOOGLE_IOS_CLIENT_ID=...` (required for `SupabaseEnv.googleConfigured` to be true on iOS, env.dart:53-58), a first-time user taps "Continue with Google". `SupabaseOAuthService.nativeGoogleSignIn` (lib/src/features/auth/data/oauth_sign_in.dart:54-55) gets null from `attemptLightweightAuthentication()` and calls `gsi.authenticate()`, i.e. the interactive path. GoogleSignIn-iOS then executes GIDSignIn.m:733-742, which builds `GIDSignInCallbackSchemes` from the client ID and compares it against `CFBundleURLTypes` read out of the app's Info.plist (GIDSignInCallbackSchemes.m:31-40). The only scheme registered here is `io.supabase.pitch` (Info.plist lines 62-74), so `unsupportedSchemes` is non-empty and the SDK does `[NSException raise:NSInvalidArgumentException format:@"Your app is missing support for the following URL schemes: %@"]`. An uncaught ObjC exception is not catchable from Dart - the process terminates. Google sign-in on iOS is a hard crash, not a failed login.

**Why it is real**

Read directly from the vendored SDK source in the project's own SPM checkout (app/build/ios/SourcePackages/checkouts/GoogleSignIn-iOS/GoogleSignIn/Sources/GIDSignIn.m:733-742 and GIDSignInCallbackSchemes.m). The google_sign_in_ios README explicitly states that passing `clientId` in Dart lets you skip the GIDClientID plist keys but that "Note that step 6 is still required" - step 6 being the reversed-client-ID CFBundleURLTypes entry. The prior fix run added the `io.supabase.pitch` scheme for the Supabase redirect and stopped there; the Google scheme is a separate, mandatory entry. The check is guarded by `options.interactive`, so the non-interactive `attemptLightweightAuthentication()` call that precedes it does not trip it - only real users signing in do.

---

## 5. [CRITICAL] insert_ball still emits 2 realtime broadcasts per shifted delivery - the Unit 5a storm fix only removed the restamp half
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260705120100_corrections_apply_guard.sql`:53

**Failure scenario**

A scorer notices a missed ball at over 1.3 of a completed 20-over innings (120 deliveries) and taps 'Insert a ball after this'. insert_ball runs the two-step seq negation: `update deliveries set seq = -(seq+1) where seq > _after_seq` touches ~112 rows, then `update deliveries set seq = -seq where seq < 0` touches the same ~112 rows again. The `deliveries_broadcast` trigger (20260616202201_broadcast.sql:23, `after insert or update or delete ... for each row`) fires on every one of those row updates, so ~225 messages land on topic `match:<id>` inside one transaction. Every connected viewer subscribes to INSERT/UPDATE/DELETE on that topic (match_viewer_screen.dart:93) and its callback is `_refold()` (match_viewer_screen.dart:101-108), which invalidates matchProvider, matchInningsListProvider and inningsStateProvider for every known innings. With 200 people watching the match, one insert tap produces ~225 x 200 x 2 = ~90,000 compute_innings_state RPCs, each a plpgsql loop over the full delivery list. The realtime quota and the DB both fall over, and the viewers see the score flicker for a minute.

**Why it is real**

Commit 73733bb explicitly named this number - 'insert_ball was worse (renumber + restamp = ~235)' - but the fix in 20260707140000_restamp_no_op_writes.sql only added the `is distinct from` guard inside restamp_innings_strike. The renumber half is untouched: lines 53-54 of 20260705120100_corrections_apply_guard.sql are still two unconditional bulk UPDATEs over every downstream row, and this file is the latest definition of insert_ball in the migration ordering. The broadcast trigger was never made statement-level or conditional (20260702140200_broadcast_logging.sql only added a raise warning). So the largest contributor to the storm survived the fix.

---

## 6. [CRITICAL] matches INSERT is still granted with only an owner_id check, so create_match's team-admin gate (SEC-5) is bypassable and any user can fabricate a permanent public match between two strangers' teams
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260616200501_matches_rls.sql`:6

**Failure scenario**

Mallory signs in with any account. `teams_select_authenticated` and `team_members_select_authenticated` are both `using (true)`, so she reads the ids of victim teams V1/V2 and of their real players. She then issues one PostgREST call:

  POST /rest/v1/matches
  {"team_a_id":"<V1>","team_b_id":"<V2>","owner_id":"<her uid>","scorer_id":"<her uid>","overs_limit":5}

`matches_insert_own` WITH CHECK only tests `owner_id = auth.uid()`; team_a_id, team_b_id and scorer_id are unchecked. The row is created, so `is_match_scorer()` (20260616200401_is_match_scorer.sql:8) now returns true for her on a match between two clubs she has no relationship with. Every downstream guard then passes because each one only asks "are you the scorer?":
- `add_squad_member` (20260707130200:19-28) accepts V1/V2's real team_members rows: the team IS in the match and the player IS in that team.
- `start_innings` (20260706111400:14) accepts, flips status to 'live', and the `notify_match_live` trigger (20260703150100:95-112) mails every registered squad member "Your match is live".
- `record_ball` and then `set_match_result` (20260706111600:14) accept; the match becomes status='complete' and a POTM is frozen onto it.

Result, all publicly readable with no login: `team_career_stats(V1)` (20260703190000:6-8, granted to anon) counts the fake game as played+lost on the team page; `player_career_stats(victim)` (20260623142000:36-43, granted to anon) folds the innings into a real player's career - a golden duck, a 0/40 spell; the match appears in `teamMatchesProvider` (app/lib/src/features/identity/data/identity_providers.dart:104-111) on both victim teams' pages. The victims cannot remove any of it: `delete_match` (20260702130000:12) and `matches_delete_owner` both require owner_id = auth.uid(), and `transfer_scorer` (20260707200000:178) refuses once status is 'complete'. The forgery is permanent.

**Why it is real**

20260701160000_create_match_admin_gate.sql added the SEC-5 rule `is_team_admin(_team_a) or is_team_admin(_team_b)` to the RPC, and test 84-create-match-admin-gate.test.sql only ever calls the RPC. 20260707130100_revoke_direct_writes.sql is the migration that hunted exactly this pattern ("the RPC holds the rule, but the TABLE is still granted") and at line 33 it revoked UPDATE on matches - but not INSERT, and it left `matches_insert_own` untouched (it says so at line 30: "The client keeps INSERT (matches_insert_own)"). No later migration alters that policy (grep over all 130 migrations for `matches_insert_own` returns only 20260616200501:6 and the comment at 20260707130100:30). Test 108-unit2-authz-hardening.test.sql covers the raw-INSERT bypass for tournament_teams and tournament_matches and the raw-UPDATE bypass for matches, but never a raw INSERT into matches. This is the same defect shape the review fixed for `posts_update_author` in the same file (20260707130100:64-71): the policy omits the authorization condition its RPC enforces.

---

## 7. [HIGH] "Block user" only closes DMs - the blocked person keeps writing on the victim's posts and pushing named notifications into their inbox, and the victim cannot remove the replies
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260616203501_post_replies.sql`:12

**Failure scenario**

A harasses B in a DM. B opens the thread menu and taps "Block user" (app/lib/src/features/messages/presentation/dm_thread_screen.dart:241-246 -> discover_repository.dart:115). A now cannot open a thread or send a DM (dm_send_allowed / get_or_create_dm_thread both consult is_blocked_between). A then goes to B's looking-for post and POSTs to /rest/v1/post_replies with {post_id, author_id: A, body: "..."}. The insert policy post_replies_insert_own only checks author_id = auth.uid() - there is no is_blocked_between call anywhere on this path - so it succeeds. The AFTER trigger notify_post_reply (20260703150100_notification_triggers.sql:6-23) then inserts a notification addressed to B whose body is A's display_name + ' replied to your post', which B sees on the Notifications screen; the body itself renders in B's post-detail replies list (postRepliesProvider, discover_providers.dart:102-107, which applies no block filter). B has no recourse: post_replies_delete_own (same file, line 14-15) scopes DELETE to author_id = auth.uid(), so only A can delete A's reply - the post owner cannot. B's only escape is to cancel their own post. request_to_join (20260707210000_notify_only_present_admins.sql:8-48) is the same shape: a blocked user can spam join requests at a team B captains and each one writes a notification naming them.

**Why it is real**

I read every consumer of is_blocked_between: it appears only in get_or_create_dm_thread (20260703140200_dm_thread_gates.sql:21) and dm_send_allowed (20260703140100_blocked_users.sql:36-47, wired into the dm_messages insert policy). Nothing else in the 170-migration set references blocked_users. The post_replies insert policy and the notification triggers are the current definitions (no later migration re-creates them). The delete policy really is author-only, which contradicts the design doc's own spec (2026-06-16-matchmaking-discovery-design.md:126 says "author/post-owner may delete"). The block affordance is presented to the user as "Block $name" with no scoping caveat, so the gap is between what the feature promises and what it does.

---

## 8. [HIGH] "Reset password" emails a link that can never re-enter the app - no redirectTo, no recovery handler, no password-update screen
- **file**: `Projects/cricket-app/app/lib/src/features/profile/presentation/settings_screen.dart`:35

**Failure scenario**

A user who signed up with email/password forgets it, opens Settings and taps "Reset password" (subtitle: "We email you a reset link"). The call is `auth.resetPasswordForEmail(email)` with no `redirectTo`, so GoTrue builds the recovery link against the project's Site URL - `http://127.0.0.1:3000` in backend/supabase/config.toml:auth.site_url, and the dashboard default for the hosted project. The user taps the link on their phone, Safari/Chrome opens `127.0.0.1:3000/#access_token=...` and shows a connection error. Even if Site URL were corrected to `https://pitch.app`, no App Link / Universal Link is registered for that domain (Runner.entitlements has only `com.apple.developer.applesignin`; AndroidManifest.xml registers only `io.supabase.pitch://login-callback`), so the browser still cannot hand off to the app. And even if it could, `grep -rn "passwordRecovery"` across lib/ returns nothing, app_router.dart has no recovery/reset route among its 38 GoRoutes, and no screen anywhere calls `updateUser(UserAttributes(password: ...))`. There is no path, by link or by OTP, for a locked-out user to set a new password.

**Why it is real**

Three independent breaks in the same chain, each verified: (1) settings_screen.dart:35 passes no `redirectTo` although a registered scheme `io.supabase.pitch://login-callback` already exists and is used at oauth_sign_in.dart:82; (2) no `AuthChangeEvent.passwordRecovery` listener - auth_providers.dart:53 handles only `signedOut`; (3) no password-entry UI exists to consume a recovery session even if one arrived. Unlike the team-invite and tournament-join links, which the fix run backstopped with manual code-entry dialogs (my_teams_screen.dart:118-125, tournaments_list_screen.dart:95-122), this flow has no fallback at all.

---

## 9. [HIGH] 'Add my team' in tournament management awaits an RPC with no try/catch, so a rejected add is a completely silent no-op
- **file**: `Projects/cricket-app/app/lib/src/features/tournaments/presentation/manage_tournament_screen.dart`:361

**Failure scenario**

The organizer taps 'Add my team' and picks a club. `_addTeam` builds its option list from `myTeamsProvider` (identity_providers.dart:8), which returns EVERY team the user is a member of with no role filter - including ones where their role is 'player'. `add_tournament_team` raises `'you must be an admin of this team to enter it'` (20260702150000_add_tournament_team_admin_gate.sql:15) for exactly that case. Line 361 awaits it with no try/catch, so the throw becomes an unhandled async error inside the tap callback: in release the user sees nothing at all - no SnackBar, no team in the list, `tournamentOverviewProvider` is never invalidated (line 362 is skipped). The organizer taps the same team repeatedly and concludes the app is broken. Line 337, `await ref.read(myTeamsProvider.future)`, is unguarded in the same method, so an offline tap on 'Add my team' also throws before the sheet even opens: the button does nothing, silently.

**Why it is real**

This is the identical defect class the previous review already fixed one method below: `_setGroup` (line 322) carries a comment saying the swallowed SEC-8 admin-gate error 'left invite-built tournaments unable to ever reach two populated groups', and it now shows a SnackBar. `_addTeam` was missed entirely and has no error handling of any kind, while `new_post_composer.dart:222-226` proves the codebase knows to filter `myTeams` down to captain/admin before offering team-admin actions.

---

## 10. [HIGH] A partially-failed squad save cannot be undone: unticking a saved player never removes them, so ghost players reach the live match
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/match_squads_screen.dart`:83

**Failure scenario**

`_next` writes the XI one row at a time in a loop (`await repo.addSquadMember(...)` per member). If the 8th of 12 calls fails, the catch at line 101 sets `_error = 'Could not save the squads.'` - implying nothing was saved - while 7 rows are already committed server-side. The scorer then adjusts the XI (unticks 3 of those 7 because they did not show up) and taps 'Next: toss' again. Only additions are sent: the app has no removal path at all (grep: `match_squad` appears in lib/ only as a SELECT in match_providers.dart:63 - there is no `removeSquadMember` in MatchRepository and no delete anywhere), so the 3 unticked players stay in `match_squad`. They then appear in the toss screen's opener dropdowns, in the console's batter/bowler/fielder pickers and on the public scorecard - and once a ball is credited to them, `player_career_stats` bakes a permanent public career record for someone who never played. The same divergence happens on the plain 'Resume setup' path: `_prefillFrom` (line 42) ticks the saved XI, and unticking anyone there is purely cosmetic.

**Why it is real**

The checkbox UI presents itself as the authoritative squad ('Next: toss (N picked)'), but the only server call is additive and idempotent (`on conflict ... do update`, 20260707130200_add_squad_member_validation.sql). Nothing in the app ever deletes a match_squad row, so any de-selection after a first (partial or complete) save silently disagrees with the server. The migration comment for that same RPC explicitly names 'a permanent, publicly-readable career record ... for someone who never played, with no user-facing way to remove it' as the harm being defended against.

---

## 11. [HIGH] AuthGate.error tears down the whole navigation stack, so a failed background profile re-read evicts a scorer mid-innings and drops them on Discover
- **file**: `Projects/cricket-app/app/lib/src/core/routing/app_router.dart`:82

**Failure scenario**

A scorer is on /matches/<id>/score. supabase_flutter auto-refreshes the JWT (~hourly, and on every resume from background), so currentSessionProvider yields a new Session and myProfileProvider re-runs `rpc('my_profile')`. The ground has bad signal, so that one call fails. skipLoadingOnReload (auth_gate.dart:31) only suppresses the LOADING state - AsyncValue.when's skipError defaults to false, so the error branch (auth_gate.dart:36) fires even though the gate is holding a perfectly good previous value. Gate -> AuthGate.error -> the redirect at app_router.dart:78-82 returns Routes.splash for every non-public location -> the router replaces the entire stack with /splash. The console, its selected bowler and any half-entered wicket dialog are gone. Tapping Retry on the splash error screen (splash_screen.dart:32) restores the gate to ready, and the ready branch then sends /splash to `onward` = Routes.discover - the scorer lands on the Discover feed, not back in the match. The same trigger fires from Edit profile's `ref.invalidate(myProfileProvider)` on save (edit_profile_screen.dart:109) and on photo change (:63).

**Why it is real**

Verified with a probe test against the real onboardingRedirect + a real GoRouter: pushed /matches/m1/score, flipped the gate to AuthGate.error, and the location became /splash with the console page gone; flipping back to ready then landed on /discover, not the console. This is the exact stack-teardown the skipLoadingOnReload fix was written to stop - the loading branch was closed and the error branch, which shares the same `return loc == Routes.splash ? null : Routes.splash` line, was left open.

---

## 12. [HIGH] Ball-log editor cannot clear a wicket: edit_ball is patch-shaped, the client never sends _clear_wicket
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/data/match_repository.dart`:208

**Failure scenario**

Scorer mis-taps WICKET (or records the wrong ball as the dismissal). They open Ball log, tap the ball, turn the "Wicket" switch OFF and hit Save. ball_log_screen.dart:618 emits `wicketType: _wicket ? _wicketType : null` -> null; MatchRepository.editBall (match_repository.dart:234-237) only adds `_wicket_type` / `_dismissed_player_id` / `_incoming_batter_id` / `_fielder_id` to the params map when they are non-null, so all four are omitted. Since 20260707130300_edit_ball_patch.sql the RPC is PATCH semantics - `wicket_type = case when _clear_wicket then null else coalesce(_wicket_type, wicket_type) end` - and `_clear_wicket` defaults to false and is never sent by any client (grep: the only occurrences are the migration and one pgTAP test). The UPDATE therefore leaves wicket_type, dismissed_player_id, incoming_batter_id and fielder_id exactly as they were. The screen then invalidates and redraws the ball still showing 'W bowled'. The fold keeps the phantom wicket: wickets count is one too high, the wrongly dismissed batter stays out, the incoming batter is at the crease, and on a small squad the innings can end 'all out' one wicket early. The scorer has no working affordance to fix it (delete + re-insert is the only path) and gets no error telling them the save was a no-op.

**Why it is real**

Both halves verified by reading the code: ball_log_screen.dart:538-543 renders the toggle and :618-628 nulls every wicket field when it is off; match_repository.dart:222-238 builds the params map with `if (x != null)` guards so nulls are omitted entirely; 20260707130300_edit_ball_patch.sql:63-71 coalesces omitted params to the existing column. The repository's own doc comment at match_repository.dart:205-207 still claims 'edit_ball is a FULL overwrite ... callers pass the complete intended state', which is the pre-20260707130300 contract - the client was never updated when the RPC semantics were inverted. Same silent-no-op applies to noball_secondary_kind (a no-ball-for-byes edited into a legal ball keeps `noball_secondary_kind='bye'`) and to the wagon shot (_clear_wagon also never sent).

---

## 13. [HIGH] Bowler picker enforces the raw rules cap, not the effective cap - every bowler goes 'At over limit' and the innings cannot continue
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:1098

**Failure scenario**

10-over match: match_repository.dart:25 stamps rules.max_overs_per_bowler = (10+4)~/5 = 2. Bowling side names a 3-player squad (start_innings only requires >= 2). Backend `_bowler_over_cap` (20260707130700_bowler_cap_feasible.sql) returns max(2, ceil(10/3)=4) = 4, so record_ball would allow 4 overs each. The console computes `atCap = legalBalls >= capOvers * bpo` from the raw rule = 2. After each of the three bowlers has bowled 2 overs (6 overs bowled), every row in the picker shows 'At over limit' and is `enabled: false` with `onTap: null`. _bowlerId stays null, the run pad stays behind AbsorbPointer, and tapping it just reopens the same all-disabled sheet. The match cannot be finished or scored further. Tighter case: 5 overs with a 2-player bowling squad (rule cap 1, effective cap 3) dead-ends at over 3.

**Why it is real**

The HIGH fix in 20260707130700_bowler_cap_feasible.sql deliberately raised the enforced cap to `greatest(rule, ceil(max_overs / bowling_squad_size))` precisely to remove this dead end, and its comment says the fix 'self-heals existing matches without an app update'. But the app never calls `_bowler_over_cap`; scoring_console_screen.dart:1078 reads `rules['max_overs_per_bowler']` straight off the match row, so the client is strictly stricter than the server and reintroduces the unfinishable-innings dead end for any bowling squad smaller than 5.

---

## 14. [HIGH] Console clears (and blocks) the bowler when an over's FIRST delivery is a wide or no-ball
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:45

**Failure scenario**

A bowls over 1; legal_balls = 6, so _afterBall stashes _lastOverBowlerId = A and clears _bowlerId. Scorer picks B. B's first delivery of over 2 is a wide. record_ball accepts it, but legal_balls is still 6, so `legal > 0 && legal % bpo == 0` is true again: _afterBall sets _lastOverBowlerId = B and _bowlerId = null. The scorer is forced back into _pickBowler mid-over, where B is now greyed out with 'Bowled last over' - the bowler who must finish his own over is the one bowler that cannot be selected. Picking anyone else credits the remaining 6 legal balls of over 2 to a bowler who never bowled them. Worse, A is now selectable (_lastOverBowlerId was overwritten with B), and record_ball's consecutive-over guard is skipped because the last delivery in the table is B's wide (`_last_legal` is false), so A legally bowls overs 1 and 2 back to back.

**Why it is real**

_afterBall's over-completion test is `legal % bpo == 0` on the count of LEGAL balls only, so it fires again for every illegal delivery that opens a new over. This is the exact same false positive that migration 20260619120000_record_ball_consec_fix.sql fixed server-side (by requiring the previous delivery to have been the over-completing legal ball); the client-side mirror of that logic was never fixed. _pickBowler (line 1100) disables `id == _lastOverBowlerId` unconditionally, so the mid-over bowler is unreachable.

---

## 15. [HIGH] DM inbox downloads every message body in every thread the user has, and the thread-id list is unbounded in a GET query string
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/discover/data/discover_providers.dart`:181

**Failure scenario**

dmInboxProvider collects every thread id the user participates in (line 167, no limit), then runs `from('dm_messages').select('thread_id, body, created_at, sender_id, read_at').inFilter('thread_id', ids).order('created_at', ascending:false)` with no `.limit()` - the entire DM history across all conversations - purely to derive a one-line preview, a timestamp and an unread count per thread (lines 186-197). Worse, this provider is watched from the Discover app bar to draw the unread badge (discover_screen.dart:79), so simply opening the headline tab pulls down every message the user has ever exchanged. Two failure modes: (a) a season-old organiser with 40 threads x 300 messages downloads ~12k message bodies on every Discover open; (b) `inFilter` serialises the ids into the GET URL as `thread_id=in.(uuid,uuid,...)` at 37 bytes each, so at roughly 200 conversations the request line passes the 8 KB header limit of Supabase's gateway and the call fails outright - the Messages screen and the Discover badge both break with no way for the user to recover.

**Why it is real**

I read the full provider body: three sequential round trips, none bounded, and the message fetch is used only for a preview string and a count that the server could compute. supabase_flutter issues `.select()` as a GET, so the id list genuinely goes in the URL. Nothing paginates and nothing caps `ids`.

---

## 16. [HIGH] Deleting the sole captain's account permanently freezes their team - no admin can ever exist again
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260707130500_delete_account_always_anonymize.sql`:43

**Failure scenario**

A team created by one person (create_team makes the creator 'captain', 20260615140801:18-19) has 10 other members who joined via invite - accept_invite always inserts role 'player'. The captain deletes their account. `update team_members set profile_id = null ... where profile_id = _me` nulls the profile on the only captain/admin row, so `is_team_admin(team)` (20260707180000_leave_team.sql:34-43, requires profile_id = auth.uid()) is false for every remaining member, forever. Consequences for the other 10: no one can add a guest (add_guest_member gates on is_team_admin), mint or revoke an invite, approve a join request or a guest claim, edit the team name/logo (teams_update_admin), create a match with this team (create_match requires admin of a participating team - 20260701160000:12), or delete the team (teams_delete_admin). The team is a museum piece with all of their stats attached to it. There is no recovery path in the app or in SQL: set_team_member_role itself requires is_team_admin.

**Why it is real**

leave_team explicitly refuses this exact state ('A team with no captain has nobody who can add players, start a match or accept an invite - it is unusable and unrecoverable from inside the app', 20260707180000:100-107) and raises 'hand the captaincy to someone else before leaving'. delete_my_account performs the same departure with no such guard, so the guarded state is reachable through the Settings screen instead of the Leave button.

---

## 17. [HIGH] Failed match/innings/squad loads are rendered as the 'not set up yet' empty state in the scoring console
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:355

**Failure scenario**

`build` only distinguishes loading from not-loading: `(match.isLoading || innings.isLoading || squad.isLoading) ? spinner : _content(match.value, innings.value, ...)`. For an AsyncError, `isLoading` is false and `.value` is null (riverpod 3.3.2 AsyncValue.value returns null on error, it does not throw), so a FAILED `currentInningsProvider` load falls into `_content` with `innings == null` and line 374 tells the scorer 'No innings yet. Finish setup first.' Concretely: the scorer taps 'Continue scoring' on a live match while the connection is down, and the app states that the match they have been scoring for 8 overs has not been set up. There is no error styling, no retry, and (same non-autoDispose caching as above) re-entering the screen shows the identical lie until the app is killed. A scorer who believes it will re-run setup: `add_squad_member` upserts and `start_innings` is called again, which is real damage on top of the wrong message.

**Why it is real**

`match.isLoading` / `innings.isLoading` are false in the error state and `.value` is null with no previous data, so the error case provably routes into the same branch as 'setup not finished'. The same file's `_content` proves the authors intended an error path (line 385 handles the innings-state error separately) - the three outer providers simply have no error branch at all. ball_log_screen.dart:31 repeats the identical `isLoading`-only shape ('No innings to correct yet.').

---

## 18. [HIGH] JOURNEY G's group-split step can never match a chip, so the journey never generates or verifies a single fixture
- **file**: `Projects/cricket-app/app/integration_test/user_journeys_test.dart`:756

**Failure scenario**

Journey G adds four teams, then tries to move teams[2] and teams[3] into group B with `find.ancestor(of: find.text(t), matching: find.byType(Row))` + `find.descendant(... ChoiceChip 'B')`. In manage_tournament_screen.dart:67-79 the team name is a ListTile `title` and the A/B chips live in `trailing: Wrap(...)`. ListTile renders through `_ListTile` (a SlottedMultiChildRenderObjectWidget, no Row anywhere in the chain) and the Wrap is a SIBLING of the title, so the ancestor Row finder matches nothing, bChip is empty, and the `if (bChip.evaluate().isNotEmpty)` at line 759 skips silently for both teams. All four teams stay in group A -> `canGenerate = byGroup['A']>=2 && byGroup['B']>=2` is false -> 'Generate group fixtures' stays disabled. tapScrolled at line 767 then taps a DISABLED FilledButton (a disabled ButtonStyleButton still hit-tests, so tester.tap neither warns nor throws) and nothing happens. Nothing in lines 767-773 asserts a fixture exists: the only post-generate assertions are findsNothing on 'PostgrestException'/'row-level security'. The tournament stays in 'setup', so the run finally dies at line 776 hunting the group-stage copy 'Finish every group match', reporting a missing-copy timeout that names the playoffs gate rather than the broken group split.

**Why it is real**

The journey's stated purpose - "four teams, groups, and a real fixture list", "THE STEP NO DEVICE RUN HAS EVER TAKEN" - is not asserted anywhere: generate_group_fixtures succeeding is only ever inferred, and the step that makes it possible silently no-ops. Per .claude/context/memory/work_status.md this journey (commit 4344210) has not yet completed a device run ('Run 26 is verifying G now'), so the broken finder has not been caught.

---

## 19. [HIGH] Match viewer has no re-sync path: one missed broadcast freezes the live score permanently, even after leaving and reopening the screen
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/match_viewer_screen.dart`:101

**Failure scenario**

A viewer is watching /watch/:id at 45/2 (8 overs). Their phone loses signal for ~30s at the ground. Broadcast has no replay, so every message emitted during the gap is gone. The socket reconnects and the channel rejoins, but nothing fires `_refold()` on reconnect - it is only called from `channel.onBroadcast` (line 94). If the scorer finished the match during the gap (the final delivery + the matches status/result UPDATE were the last broadcasts), no further message will ever arrive on that topic. The screen shows 45/2 with the red LIVE badge forever. There is no pull-to-refresh: the viewer body is plain ListViews (lines 566, 789, 932, 1079) and it is the only data screen in the app without a RefreshIndicator (live_matches_screen.dart:23, matches_screen.dart:70, profile_screen.dart:70, player_stats_screen.dart:41 all have one). Backing out to the Watch-live list and tapping the match again does NOT help: matchProvider / matchInningsListProvider / inningsStateProvider are plain FutureProvider.family (match_providers.dart:50, 88, 120) - riverpod 3.3.2 defaults isAutoDispose to false (riverpod/lib/src/builder.dart:235) - so the container replays the cached stale AsyncData with no refetch. Only a full app restart recovers. The same dead state is reached when the owner calls delete_match on a live match (20260702130000_rpc_delete_match.sql has no status guard) because matches_broadcast is `after update` only and a DELETE never notifies anyone.

**Why it is real**

`_refold()` (lines 101-108) is invoked from exactly one place, the broadcast callback; the only other invalidations of these providers in the whole app are the error-retry button (lines 324-327, which is unreachable because the state is `hasValue`, not error) and the scorer's own console. Verified by grep across lib/: no RefreshIndicator, no WidgetsBindingObserver/AppLifecycleListener, and no subscribe-status callback on `channel.subscribe()` (line 96) that could trigger a catch-up fetch after a rejoin. The provider default was confirmed against the installed riverpod-3.3.2 source.

---

## 20. [HIGH] Player/team search is an unanchored ILIKE with no trigram index - a full scan of profiles and teams on every keystroke
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260706111000_search_handle.sql`:11

**Failure scenario**

search_players_and_teams filters with `p.display_name ilike '%' || trim(_query) || '%'`, `p.handle ilike '%' || ... || '%'` and `t.name ilike '%' || ... || '%'`. A leading-wildcard ILIKE cannot use a btree index, and there is no pg_trgm GIN/GIST index anywhere in the migration set (I grepped every `create index` - profiles has only profiles_phone_idx and profiles_handle_lower_uidx, teams only teams_created_by_idx). Every call is therefore a sequential scan of the whole profiles table plus the whole teams table, and the `limit 15` is applied only after that scan. Combined with the client firing one call per keystroke (search_screen.dart:57), typing 'Rohit Sharma' triggers 11 full scans of both tables. At 2M profiles that is ~22M rows read for one user typing one name, and concurrent searchers will saturate the instance.

**Why it is real**

Read the RPC body and confirmed the absence of any trigram/GIN index across all migrations. The subtitle ordering clause `order by (p.handle ilike ... || '%') desc` also cannot be index-assisted. The cost scales with total registered users, not with anything about the searcher.

---

## 21. [HIGH] Public 'Watch live' list seq-scans and sorts the entire matches table on every open - no index on status, no limit
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/data/match_providers.dart`:169

**Failure scenario**

liveMatchesProvider issues `from('matches').select(...).inFilter('status',['live','innings_break']).order('created_at', ascending:false)` with no `.limit()`. public.matches (20260616200301_matches.sql:21-22) has indexes only on scorer_id and owner_id - nothing on status and nothing on created_at. After a season with 500k recorded matches, every open of the login-free Watch-live screen (and every pull-to-refresh) forces a full sequential scan of matches plus a sort of the whole result, to return maybe 30 live rows. This is anon-reachable, so it is also the cheapest way for an unauthenticated client to burn the database: a loop of refreshes is 500k row reads each. Once the scan exceeds the PostgREST statement timeout the screen shows 'Could not load live matches' permanently.

**Why it is real**

I read both the provider (no limit anywhere in the chain, lines 169-177) and the table DDL (20260616200301_matches.sql, only matches_scorer_idx and matches_owner_idx). The cost is a function of total matches ever played platform-wide, not of anything the caller owns.

---

## 22. [HIGH] The onboarding gate never sees a pushed /sign-in, so a successful sign-in leaves the user sitting on the sign-in form and the whole `next` / signInThenReturnTo mechanism is dead code
- **file**: `Projects/cricket-app/app/lib/src/core/routing/app_router.dart`:128

**Failure scenario**

Every sign-in entry point is an imperative push: discover_screen.dart:172, profile_screen.dart:50, post_detail_screen.dart:56, invite_accept_screen.dart:121, join_tournament_screen.dart:98. go_router's optionURLReflectsImperativeAPIs defaults to false, so after `context.push('/sign-in')` the router's RouteMatchList.uri stays the BASE location ('/discover'); that is what gets reported back to the RouteInformationProvider and what the refreshListenable re-parse feeds to the top-level redirect as state.matchedLocation. Concretely: an anonymous user on Discover taps Sign in, enters dev@pitch.local / password123 (or Continue with Google) as an EXISTING account. The gate flips anonymous -> ready. The redirect runs with loc='/discover', which the ready branch (app_router.dart:103-108) leaves alone because it only matches splash/signIn/createProfile - so nothing navigates and the user is still staring at the Sign in form with no feedback, and must guess to press back. Worse for the link flows: from /invite/<token>, `context.push(Routes.signInThenReturnTo(...))` produces loc='/invite/<token>', which the public-bypass at app_router.dart:65-71 returns null for - so (a) the ?next= destination is never consumed, and (b) a brand-new account (AuthGate.needsProfile) is never routed to create-profile either. If that profile-less user backs out and taps 'Join team', accept_invite inserts team_members.profile_id = auth.uid() against a profiles FK (migrations/20260615140501_team_members.sql:4) and they get a raw 23503 rendered as 'Could not join: PostgrestException...'.

**Why it is real**

Verified with probe tests driving a real GoRouter with the real onboardingRedirect: (1) push('/sign-in') from /discover then gate->ready leaves SIGNIN on screen and the location at /sign-in; (2) push(signInThenReturnTo('/invite/tok1')) from /invite/tok1 then gate->ready leaves SIGNIN on screen and never resolves to /invite/tok1; (3) the same push then gate->needsProfile also leaves SIGNIN on screen and never reaches create-profile. Only the case where the base location itself needs a redirect works (gate->needsProfile from /discover correctly replaces the stack with create-profile) - which is exactly the only path the integration journeys exercise, since every journey uses 'Create test account (dev)' (user_journeys_test.dart:104-125, rebuild_gate_test.dart:56-64). test/router_redirect_test.dart only calls onboardingRedirect as a pure function, so no test drives the push-then-flip sequence.

---

## 23. [HIGH] The scoring console has no error branch: a transient failure loading the match/innings renders 'No innings yet. Finish setup first.' permanently, locking the scorer out of a live match until the app is force-quit
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:355

**Failure scenario**

A scorer opens /matches/<id>/score while the connection is momentarily down. build() only branches on isLoading (line 355), so the AsyncError falls through to _content(match.value=null, innings.value=null, ...), and _content's first guard (line 373-374) renders 'No innings yet. Finish setup first.' - a message that tells the scorer of a live match to go redo setup. matchProvider / currentInningsProvider / matchSquadProvider are plain (non-autoDispose) FutureProvider.family instances (match_providers.dart:50, 74, 61), so the failed future is cached for the life of the ProviderContainer, and the console invalidates them only after a successful action. Backing out to Matches and re-entering the console re-reads nothing and shows the same message; there is no Retry. The scorer's only recoveries are killing the app, or following the misleading instruction into 'Resume setup' -> squads -> toss, where startInnings then fails because innings 1 already exists. Contrast match_viewer_screen.dart:311-330, which got an explicit not-found / error+Retry treatment (RT-5) for the same providers.

**Why it is real**

Read both code paths: build() at :355 tests only .isLoading, so AsyncError reaches _content with null values, and _content at :373 has no way to distinguish 'setup incomplete' from 'load failed'. The permanent-cache half of this is a known trap in this codebase - match_providers.dart:20-23 documents adding .autoDispose to opponentSearchProvider precisely because 'a search that failed on a dropped connection stays cached as a failure, so retyping the same name never retries' - and the fix was never applied to the match/innings/squad providers the console depends on.

---

## 24. [HIGH] Turning 'Wicket' off in the ball-log editor is a silent no-op - a mis-tapped wicket cannot be un-recorded
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/data/match_repository.dart`:234

**Failure scenario**

Scorer taps WICKET by mistake on a ball that was really a single. They open the ball log, tap the ball, Edit, switch the 'Wicket' toggle OFF, set runs to 1, Save. _BallEditorSheet emits `wicketType: null, dismissedId: null, incomingId: null` (ball_log_screen.dart:618-627). editBall only adds `_wicket_type` / `_dismissed_player_id` / `_incoming_batter_id` to the params map `if (... != null)`, so all three are omitted. edit_ball is now PATCH semantics - `wicket_type = case when _clear_wicket then null else coalesce(_wicket_type, wicket_type) end` - and `_clear_wicket` is never sent by the app (`grep -rn _clear_wicket app/lib` finds nothing). The update therefore keeps wicket_type, dismissed_player_id and incoming_batter_id exactly as they were. The sheet closes with no error, the providers are invalidated, and the scorecard still shows the batter dismissed and the incoming batter at the crease. Only the runs changed.

**Why it is real**

20260707130300_edit_ball_patch.sql converted edit_ball from full-overwrite to patch semantics and reasoned that 'the app sends runs/wides/no-ball/byes/leg-byes ... and omits the rest, which is now preserved instead of wiped'. That is correct for the extras it enumerates, but the client also omits the wicket columns whenever the scorer is trying to CLEAR them, which under the old overwrite semantics did clear them. match_repository.dart:205-207 still documents the old contract ('edit_ball is a FULL overwrite ... callers pass the complete intended state'), so client and server now disagree about what an omitted wicket means.

---

## 25. [HIGH] Un-ticking a saved squad member on a resumed setup is silently discarded (no removal write exists)
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/match_squads_screen.dart`:83

**Failure scenario**

Scorer picks an XI, taps "Next: toss", then backs out without starting (match stays in `setup`). Later: Matches tab -> tile -> "Resume setup" reopens MatchSquadsScreen, which prefills `_selected` from `matchSquadProvider` (`_prefillFrom`, line 42). The scorer un-ticks a player who cannot make it (the checkbox at line 308 removes the id from the local `_selected` set only), ticks a replacement, and taps "Next: toss". `_next` (line 63) loops over `_selected` and calls only `repo.addSquadMember` (line 83); it never deletes the row for the un-ticked player. `ref.invalidate(matchSquadProvider(...))` at line 99 then refetches the SERVER truth, so the toss screen's opening-pair dropdowns (toss_openers_screen.dart:56-59, built from `matchSquadProvider`) still list the removed player, the console's incoming-batter and fielder lists still offer him (scoring_console_screen.dart:1189-1198), and he appears on the public scorecard. Worse, `_next` renumbers `battingOrder` 1..N over the NEW selection while the un-ticked row keeps its old order value, so two squad rows now share a `batting_order` and `matchSquadProvider`'s `.order('batting_order')` (match_providers.dart:70) returns an arbitrary order between them.

**Why it is real**

There is no removal path anywhere: `grep -rn "match_squad|remove_squad" app/lib` finds only the read in match_providers.dart, MatchRepository has no delete/remove method (match_repository.dart has only `addSquadMember`), and no `remove_squad_member` / `delete from public.match_squad` exists in backend/supabase/migrations. `add_squad_member` is `on conflict do update` (20260707130200_add_squad_member_validation.sql), so re-adds are upserts and nothing ever shrinks the squad. The user's explicit removal produces no error and no server change.

---

## 26. [HIGH] auth_gate_reload_test re-implements authGateProvider instead of using it, so deleting the CRITICAL skipLoadingOnReload fix leaves the suite green
- **file**: `Projects/cricket-app/app/test/auth_gate_reload_test.dart`:52

**Failure scenario**

The file has no `package:pitch_app` import at all (verified: it and query_ordering_test.dart are the only two such files in app/test). It declares its own `_profileProvider` and `_gateFrom(...)`, and `observe(skipLoadingOnReload: true)` passes the flag to that local replica. Remove `skipLoadingOnReload: true` from lib/src/core/auth/auth_gate.dart:31 and both tests still pass: test 1 passes because the replica is still told `true`, and test 2 passes because it deliberately asks for `false`. Nothing else in app/test references skipLoadingOnReload, and router_redirect_test only exercises onboardingRedirect(AuthGate.loading, ...) -> Routes.splash, which is the downstream half. So the regression the file's own header calls CRITICAL - a background JWT refresh flipping the gate to loading and the router tearing the whole tab shell down to /splash mid-innings - has zero coverage of the app's actual code.

**Why it is real**

The replica also diverges from the real gate (`error: (_, _) => _Gate.loading` vs `AuthGate.error` in auth_gate.dart:36), proving it is a model rather than the thing under test. Its two assertions only prove a Riverpod API fact about `when()`'s default, which is true regardless of what the app does.

---

## 27. [HIGH] delete_my_account nulls out the departing user's memberships without the last-captain guard leave_team enforces, permanently bricking any team they solely captained
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260707130500_delete_account_always_anonymize.sql`:40

**Failure scenario**

Alice creates "Sunday XI" via `create_team`, which makes her the sole captain (20260615140801:19). She adds Bob and Carol as role='player'. Alice then uses Settings -> Delete account (app/lib/src/features/profile/presentation/settings_screen.dart:106), which calls `delete_my_account`. Step 2 of that function runs:

  update public.team_members
     set profile_id = null,
         guest_name = coalesce(guest_name, 'Deleted user')
   where profile_id = _me;

Alice's captain row survives with profile_id = null, so `is_team_admin('Sunday XI')` (20260707200000-era definition, 20260707180000:36-45, which matches on `profile_id = auth.uid()`) is now false for every living human. The team is still on Bob's and Carol's "My teams" list and still opens, but every admin-gated surface is dead for them and there is no recovery path anywhere in the schema:
- `add_guest_member` / `create_team_invite` / `respond_join_request` raise 'not authorized'
- `team_members_insert_admin`, `teams_update_admin`, `teams_delete_admin` all fail, so they cannot add anyone, rename it, or delete it
- `create_match` raises 'must be an admin of one of the participating teams', so the team can never play again
- `set_team_member_role` requires `is_team_admin` first (20260707200000:215), so no member can promote themselves

Bob and Carol are left with a team carrying all their match history that nobody can ever administer, and the only exit is to abandon it and start a new team from scratch.

**Why it is real**

This exact invariant is guarded on the other departure path: `leave_team` refuses with 'hand the captaincy to someone else before leaving' when the leaver is the last captain (20260707180000:78-84), and its own comment at :76-77 spells out the consequence - "A team with no captain has nobody who can add players, start a match or accept an invite - it is unusable and unrecoverable from inside the app." `delete_my_account` performs the same effective departure for every team the user belongs to and carries no such check; grep for 'captain' across all migrations shows the guard appears only in leave_team and set_team_member_role, never in delete_my_account. tests/97-delete-account.test.sql does not construct a sole-captain team. The orphaned row also keeps role='captain', so the last-captain counters in leave_team:78-81 and set_team_member_role:218-222 still count a membership that grants nobody anything.

---

## 28. [HIGH] edit_ball / insert_ball accept dismissals that are impossible off a no-ball or wide, and the ball-log editor offers them
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707130300_edit_ball_patch.sql`:54

**Failure scenario**

In the ball log, tap any delivery -> 'Edit this ball' -> Delivery = 'No-ball' -> Wicket ON -> type 'bowled' (or 'caught'/'lbw'/'stumped'/'hit_wicket') -> pick an incoming batter -> Save. edit_ball performs only `correction_wicket_guard` (incoming-batter presence) and writes the row. compute_innings_state then counts the wicket, credits the BOWLER with it (`wicket_type in ('bowled','caught','lbw','stumped','hit_wicket')`), and swaps the incoming batter in - a batter recorded as bowled off a no-ball. The same combination via 'Insert a ball after this' goes through insert_ball, which also has no dismissal-legality check. Wide + 'bowled'/'caught'/'lbw' is equally accepted, and a wicket typed 'bowled' on the ball after a no-ball (a free hit) is accepted too.

**Why it is real**

record_ball enforces both laws ('illegal dismissal on a no-ball/free-hit' restricted to run_out/obstructing/hit_ball_twice; 'illegal dismissal on a wide' restricted to hit_wicket/obstructing/run_out/stumped) - see 20260707130400_reject_retirement_as_ball.sql:58-61. `grep -rn "illegal dismissal"` across migrations shows those strings exist only in record_ball revisions; neither edit_ball (20260707130300:54) nor insert_ball (20260705120100:51) has them. And ball_log_screen.dart:548-551 lists all eight wicket types regardless of the Delivery chip selected, so the illegal combination is one tap away and the resulting bogus wicket bakes into compute_innings_cards, matches.potm and career stats.

---

## 29. [HIGH] player_career_stats and player_recent_form scan every complete match in the database; match_squad has no index on team_member_id
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260623142000_player_career_stats.sql`:36

**Failure scenario**

The innings loop is driven by `select i.id from innings i join matches m on m.id = i.match_id where m.status='complete' and exists (select 1 from match_squad ms where ms.match_id = m.id and ms.team_member_id = any(_members))`. There is no index on matches(status) and no index on match_squad(team_member_id) - 20260616200601_match_squad.sql:13 creates only match_squad_match_idx(match_id), and the `unique(match_id, team_member_id)` constraint's btree leads with match_id so it cannot serve a team_member_id lookup. The planner must therefore either seq-scan matches (filtering status) with a semi-join probe per row, or seq-scan match_squad in full. player_recent_form (20260623143000_player_recent_form.sql:17-24) repeats the identical anti-join, and `select count(distinct match_id) from v_player_matches where player_key = _player_key` (line 34) filters on `coalesce(tm.profile_id, tm.id)`, an expression no index covers. All three run inside player_public_profile, which is granted to anon. So an unauthenticated visitor opening /player/<id> for a player with 6 matches makes the server read every match_squad and matches row in the database - three times.

**Why it is real**

Verified by reading the two RPCs, the v_player_key/v_player_matches view definitions (20260623141000_player_views.sql), the match_squad DDL, and the full grep of every `create index` in migrations/. The starting relation is the global match set rather than the player's own memberships, so the cost is proportional to total DB size and is reachable without a login.

---

## 30. [HIGH] respond_join_request marks a join request 'approved' but silently fails to re-add anyone who previously left the team, because the insert conflicts with their left_at tombstone and does nothing
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260703190100_team_join_requests.sql`:77

**Failure scenario**

Ravi is on Sunday XI and has played matches, so `leave_team` (20260707180000:100) keeps his row and stamps `left_at`. Later he wants back in. He opens the team page and taps "Request to join": `request_to_join` was fixed to filter `left_at is null` (20260707200000:94-98) so the request is created and the captain is notified. The captain taps Approve. `respond_join_request` runs:

  insert into public.team_members(team_id, profile_id, role)
  values (_team, _requester, 'player')
  on conflict (team_id, profile_id) where profile_id is not null do nothing;
  update public.team_join_requests set status = 'approved' ...

Ravi's tombstone row already satisfies the partial unique index `team_members_unique_profile`, so the insert hits ON CONFLICT DO NOTHING. `left_at` is never cleared. The request is nevertheless flipped to 'approved'. No exception is raised, so the app's catch block (app/lib/src/features/teams/presentation/team_page_screen.dart:771-779) never fires: the request vanishes from the pending list, `teamRosterProvider` is invalidated and re-renders without Ravi, and nobody is told anything. `is_team_member`/`is_team_admin` still return false for him, `myTeamsProvider` (which filters `left_at is null`) still omits the team, and he cannot request again in a way that helps - each new approval repeats the same silent no-op. There is no other route back in unless an admin happens to mint an invite link, because that is the only path that was taught to revive a tombstone.

**Why it is real**

20260707200000_rejoin_after_leaving.sql exists precisely to fix this class and enumerates five call sites it repaired - accept_invite, request_to_join, add_guest_member, transfer_scorer, set_team_member_role. `respond_join_request` is not among them; grep for `respond_join_request` across backend/supabase/migrations returns only 20260703190100 (definition at :60, grants at :83-84), so the version still installed is the original one with the un-revived `do nothing`. accept_invite got the explicit revival branch (20260707200000:70-75) that respond_join_request lacks, which shows the fix was understood and simply not applied here. The only pgTAP coverage, tests/99-team-stats-join.test.sql, approves a requester who has never been on the team, so the tombstone path is untested.

---

## 31. [HIGH] respond_join_request never revives a left_at tombstone, so a departed player can never rejoin (approval silently no-ops)
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260703190100_team_join_requests.sql`:75

**Failure scenario**

Alice is a real member of team T and has played a match. She (or an admin) uses leave_team -> she has history, so 20260707180000_leave_team.sql line 100 keeps her row and sets left_at = now(). teamRosterProvider filters left_at (identity_providers.dart line 66), so team_page_screen.dart line 119 shows her the "Request to join" button. request_to_join now succeeds (its already-a-member check filters left_at, 20260707200000 line 96). An admin taps Approve -> respond_join_request runs `insert into team_members(team_id, profile_id, role) values (_team, _requester, 'player') on conflict (team_id, profile_id) where profile_id is not null do nothing`. Alice's tombstone row already satisfies the partial unique index team_members_unique_profile, so the insert is swallowed by DO NOTHING and left_at is never cleared. Line 78 then marks the request 'approved'. Result: the admin sees the request vanish as approved, Alice is not on the roster, is_team_member/is_team_admin still return false, she cannot be put in a squad, and her team page still offers "Request to join". She can re-request forever (the pending check looks for status='pending', which is now 'approved') and every approval does nothing. There is no in-app path back onto the team.

**Why it is real**

20260707200000_rejoin_after_leaving.sql explicitly enumerates and fixes the five tombstone re-entry paths (accept_invite, request_to_join, add_guest_member, transfer_scorer, set_team_member_role) - respond_join_request is the sixth and is not in the list. grep confirms respond_join_request is defined exactly once, in 20260703190100, and is never redefined. accept_invite got the revival branch (20260707200000 lines 61-79); respond_join_request kept the bare `do nothing`. Test 117 asserts request_to_join is now allowed for a departed member (line 91) but never follows through to the approval, so the newly-opened flow terminates in a dead end that no test covers.

---

## 32. [MEDIUM] 'dev credentials are debug-only' computes the prefill inside the test, so shipping dev@pitch.local/password123 in a release binary would not fail it
- **file**: `Projects/cricket-app/app/test/unit3_regression_test.dart`:54

**Failure scenario**

The test does `final prefillEmail = kDebugMode ? 'dev@pitch.local' : '';` and then asserts on that local value. It never imports or pumps SignInScreen. Under `flutter test` kDebugMode is true and kReleaseMode is false, so only the else-branch runs and it asserts that a string the test just built is non-empty. Remove the `kDebugMode ?` guards from lib/src/features/auth/presentation/sign_in_screen.dart:28-30 (which prefill a real account on the hosted project) and the test stays green; the kReleaseMode branch is dead code because widget tests never run in release mode.

**Why it is real**

The behaviour the test is named for - a release build must not carry working credentials for the hosted Supabase project - is asserted against a literal in the test file rather than against the screen, so the suite cannot detect the revert.

---

## 33. [MEDIUM] A failed people search is presented as 'No players found', and the cached failure means the same name can never be retried
- **file**: `Projects/cricket-app/app/lib/src/features/messages/presentation/dm_inbox_screen.dart`:202

**Failure scenario**

The 'New message' picker reads `results.value ?? const []` and then renders `Text('No players found.')` whenever the list is empty. `searchProvider` (discover_providers.dart:124) is a non-autoDispose family keyed by the query string, so when `search_players_and_teams` fails (dropped connection, RLS), the picker tells the user their team-mate is not on Pitch, and the AsyncError for that exact query is cached for the session - retyping the same name returns the cached failure without another request, so the user can never get a different answer for that person. The same empty-vs-error conflation shows a false 'No players found.' during every load, and search_screen.dart:66 (which does render 'Search failed.') is equally un-retryable for a repeated query. team_page_screen.dart:723 has the same shape on the other side of the fence: `pendingJoinRequestsProvider(teamId).value ?? const []` means a failed read renders as 'no join requests', so a captain sees an empty section instead of the players waiting to join.

**Why it is real**

`.value ?? const []` discards the error state by construction, and the widget then attributes the empty list to 'no results'. The retry half is the documented consequence of a non-autoDispose keystroke-keyed family - the fix already applied to `opponentSearchProvider` (match_providers.dart:19-23) for this exact reason was never applied to `searchProvider`.

---

## 34. [MEDIUM] Abandoning a match from the Matches list refreshes only myMatchesProvider, so the viewer still shows it as LIVE
- **file**: `Projects/cricket-app/app/lib/src/features/matches/presentation/matches_screen.dart`:234

**Failure scenario**

Scorer opens the console for a live match (this caches `matchProvider(id)` with `status: 'live'`, `result: null`; both are non-autoDispose so the value is kept for the whole app session). They pop back to Matches and use the tile overflow -> "Abandon match" -> confirm. `_confirmAndRun` invalidates only `myMatchesProvider` (line 234), so the tile correctly moves to Completed/"Abandoned" - but `matchProvider(id)`, `liveMatchesProvider` and `teamMatchesProvider` keep the pre-abandon row. Tapping the now-completed tile pushes `Routes.viewMatch(id)`, and MatchViewerScreen reads that stale `matchProvider` row: `_LiveTab` computes `live = match['status'] == 'live' && ...` (match_viewer_screen.dart:529) and renders the red LIVE badge with no result banner, and the Info tab prints `Status: live` (line 1093). "Watch live" (live_matches_screen.dart:20) also still lists the abandoned match as live. The viewer's realtime `_refold` cannot fix it: it subscribes on open, after the UPDATE broadcast already fired.

**Why it is real**

`matchProvider`/`liveMatchesProvider` are plain `FutureProvider`s (match_providers.dart:50, 169) and riverpod 3 keeps non-autoDispose state until the container dies (`super.isAutoDispose = false` in riverpod-3.3.2 lib/src/providers/future_provider.dart:107). The console's own `_finishMatch` invalidates `matchProvider` for precisely this reason (scoring_console_screen.dart:661); the list-level abandon path does not.

---

## 35. [MEDIUM] Account deletion keeps all DM threads and message bodies, while the app promises it 'permanently removes your profile, posts and messages'
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260707130500_delete_account_always_anonymize.sql`:36

**Failure scenario**

A user has DM'd several strangers from Discover (real names, phone numbers, addresses pasted into chat - the app's own matchmaking flow encourages 'message the author'). They delete their account after the confirm dialog at app/lib/src/features/profile/presentation/settings_screen.dart:87 states 'This permanently removes your profile, posts and messages.' delete_my_account deletes profile_private, posts, notifications, blocks, locations and join requests - but never dm_messages, dm_participants or dm_threads. These cascade off profiles, and the profiles row is deliberately kept, so nothing removes them. Every counterparty keeps the full conversation verbatim. Worse, because the profiles row survives with display_name 'Deleted user', search_players_and_teams still returns the account for any query matching 'deleted' (or a 2-char substring of it), and get_or_create_dm_thread still succeeds against it (its only checks are: profile exists, not blocked, rate limit) - so users can open and send into a thread with an account that can never read it, with no error and no indication.

**Why it is real**

Read the full RPC body: the delete list at lines 31-36 has no dm_* statements, and step 3 deliberately preserves the profiles row (line 45-47), so the ON DELETE CASCADE on dm_messages.sender_id never fires. This is both a false statement in a GDPR/store-compliance deletion dialog and a live dead-end conversation surface.

---

## 36. [MEDIUM] An in-progress tournament is orphaned when the organizer deletes their account - it can never be advanced or completed
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260625150100_tournaments.sql`:29

**Failure scenario**

An organizer runs an 8-team tournament: group fixtures generated, several played. They delete their account. tournaments.organizer_id still points at the (now banned, unsignable-in) uuid, and every management RPC is gated on `is_tournament_organizer` = `organizer_id = auth.uid()`: add_tournament_team, set_tournament_team_group, generate_group_fixtures, generate_playoffs, advance_playoffs, resolve_tied_fixture. No transfer-organizer RPC exists anywhere in the migrations, and the tournaments_write_organizer RLS policy is the same condition, so no other user can update organizer_id either. The public /tournament/:id page stays visible with a half-finished bracket: group matches can still be scored (a team admin can take scoring via transfer_scorer), but semifinals can never be generated, the final never created, champion_team_id never set. Every enrolled team is stuck in a tournament that can never end.

**Why it is real**

Grep of all migrations shows organizer_id is only ever written by create_tournament; is_tournament_organizer is the sole gate on all six management RPCs plus the tournament_teams/tournament_matches RLS policies; delete_my_account touches profiles, memberships and auth only, never tournaments. The account is banned_until 'infinity' with identities deleted, so the organizer cannot come back to finish it.

---

## 37. [MEDIUM] Android auto-backup is on by default, so the Supabase refresh token leaves the device in the user's cloud backup
- **file**: `Projects/cricket-app/app/android/app/src/main/AndroidManifest.xml`:4

**Failure scenario**

supabase_flutter 2.15 persists the session (access + refresh token) in SharedPreferences - `SharedPreferencesGotrueAsyncStorage` / `SharedPreferencesLocalStorage` in supabase_flutter-2.15.0/lib/src/local_storage.dart:66-129 - which lands in `/data/data/dev.pitch.pitch_app/shared_prefs/`. The `<application>` element declares only `label`, `name` and `icon`, so `android:allowBackup` defaults to true and there is no `android:dataExtractionRules` or `android:fullBackupContent` excluding that directory. Android Auto Backup therefore uploads the token store to the user's Google Drive and Device-to-Device transfer copies it. Anyone who can restore that backup - an attacker who has compromised the Google account, or a device-to-device transfer to a phone the user no longer controls - installs Pitch and is silently signed in as that user with a valid refresh token, without ever knowing the Pitch password, and can then read DMs, post, score matches and delete the account.

**Why it is real**

Both halves verified in-repo: the manifest genuinely omits every backup attribute (lines 4-7), and the storage backend is SharedPreferences, confirmed by reading the pinned supabase_flutter source rather than assuming. `enable_refresh_token_rotation = true` (config.toml) does not help - the restored token is unused and therefore still valid. The app has no `flutter_secure_storage` or Keystore-backed `LocalStorage` override anywhere in lib/.

---

## 38. [MEDIUM] Android session tokens leave the device: allowBackup defaults to true and supabase_flutter persists the refresh token in plaintext SharedPreferences
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/android/app/src/main/AndroidManifest.xml`:4

**Failure scenario**

The <application> tag sets label/name/icon only - no android:allowBackup="false", no android:dataExtractionRules, no android:fullBackupContent, and there is no res/xml backup-rules file in the project (res/ contains only drawable, mipmap and values folders). Android therefore treats the app as backup-and-transfer eligible for both cloud backup and device-to-device transfer. main.dart:15-18 calls Supabase.initialize with no localStorage override, so supabase_flutter uses its default SharedPreferences-backed session store: the access token AND the long-lived refresh token sit as cleartext JSON in /data/data/dev.pitch.pitchApp/shared_prefs/. Concrete path: an attacker with brief physical access (or the recipient of a second-hand/RMA device, or anyone who compromises the user's Google account and triggers a restore-to-new-device) obtains that shared_prefs blob, drops it into a fresh install, and the app comes up signed in as the victim - no password, no OTP. The refresh token does not expire on its own, so the window is indefinite. With that session the attacker reads the victim's phone number (my_profile(), 20260701120200, is the only reader of the self-only profile_private table), their exact saved home coordinates (my_home_location(), 20260625120000:6-14), every DM thread and body, and can call delete_my_account().

**Why it is real**

Verified by absence: grep for allowBackup / dataExtractionRules / fullBackupContent across the whole android/ tree returns zero hits, and `ls -R android/app/src/main/res` shows no xml/ directory, so no rules file exists and the platform defaults (allow) apply. Verified the storage choice by reading main.dart - Supabase.initialize is called with url and publishableKey only, no localStorage argument, and there is no flutter_secure_storage dependency in pubspec.yaml, so the package default is what ships. The two things the token unlocks are the two things the schema went out of its way to protect: profile_private (isolated specifically because phone is PII, 20260701120100) and profile_locations (never client-readable except for the owner, 20260625120000). Neither prior review mentions backup, SharedPreferences, secure storage, or credentials at rest.

---

## 39. [MEDIUM] Async error branches offer no retry while the providers behind them cache the failure for the session
- **file**: `Projects/cricket-app/app/lib/src/features/matches/presentation/matches_screen.dart`:49

**Failure scenario**

`matches.when(error: (e,_) => Center(Text(humanError(...))), data: (rows) => RefreshIndicator.adaptive(...))` puts pull-to-refresh INSIDE the data branch only. A user opens the app on the underground: `myMatchesProvider` fails, the Matches tab shows 'Could not load matches.' with nothing to tap, and because `myMatchesProvider` is a non-autoDispose FutureProvider the AsyncError is cached - switching tabs and coming back, or navigating away and returning, re-watches the same errored element without re-running the query. Signal returning does not fix it; only creating a match (which happens to `ref.invalidate(myMatchesProvider)`) or killing the app does. The same shape leaves these screens dead after one failed load: dm_inbox_screen.dart:100, notifications_screen.dart:83, my_teams_screen.dart:82, tournaments_list_screen.dart:48 (no refresh anywhere), claim_inbox_screen.dart:52, transfer_scorer_screen.dart:58, toss_openers_screen.dart:37/54, match_squads_screen.dart:116, tournament_page_screen.dart:47.

**Why it is real**

live_matches_screen.dart shows the correct pattern in the same codebase - the RefreshIndicator wraps `when`, and its error branch is a ListView, so the error state is pull-to-refreshable. The caching half is documented by the project itself in match_providers.dart:19-22 ('a search that failed on a dropped connection stays cached as a failure, so retyping the same name never retries'), and grep confirms `.autoDispose` appears exactly once in lib/, so every other provider retains its error.

---

## 40. [MEDIUM] DM inbox opens one realtime channel per thread and refetches the entire inbox on every inbound message
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/messages/presentation/dm_inbox_screen.dart`:58

**Failure scenario**

_syncSubscriptions subscribes to every thread in the (unbounded) inbox list and the callback is `rt.listen(id, (_) => ref.invalidate(dmInboxProvider))`. Two problems compound. First, a user with 150 conversations joins 150 private realtime channels on entering Messages; Supabase Realtime caps channels per client (default 100), so past that point the later joins are rejected and those conversations silently stop updating live - the exact class of failure the shared-channel refactor was written to prevent. Second, every inbound message on any thread invalidates the whole inbox provider, which re-runs the three-query fetch including the unbounded dm_messages download (discover_providers.dart:181). A ten-message burst in one conversation triggers ten full re-downloads of the user's entire message history back to back.

**Why it is real**

Read _syncSubscriptions (lines 45-60): `wanted` is built from every row of the inbox with no cap, and every listener's action is a blanket invalidate rather than a targeted row update. The unbounded fetch it re-triggers is the same one flagged separately above, so the two defects multiply.

---

## 41. [MEDIUM] DM thread never re-syncs after a socket gap: messages sent while the phone is offline are silently missing from the open conversation
- **file**: `Projects/cricket-app/app/lib/src/features/messages/presentation/dm_thread_screen.dart`:95

**Failure scenario**

A and B are chatting with the thread open on both phones. A's phone drops connection for 20s. B sends three messages; the DB trigger broadcasts them on dm:<threadId> but A's socket is down and broadcast has no replay. A's socket reconnects and the channel rejoins. `_messages` only ever grows through the broadcast callback (line 100-109) - history is fetched exactly once in `_init()` (line 50-61) and nothing refetches after that. A's thread therefore shows the conversation with a three-message hole, with no gap indicator and no way to reload: the message ListView (line 257) has no RefreshIndicator, and `_retryLoad()` (line 76) is only reachable from the `_loadError` branch, which is not set because the initial load succeeded. A then replies, and the two sides are talking past each other. The same silent failure occurs if the initial `subscribe()` join is rejected - there is no subscribe-status callback (dm_realtime.dart:51), so the thread just never goes live.

**Why it is real**

Read both files end to end: DmRealtime.listen creates the channel and attaches only an INSERT broadcast handler; the screen's `_ids`/`_messages` are append-only from that handler. No app-lifecycle observer exists anywhere in lib/ (grep for didChangeAppLifecycleState / AppLifecycleListener returns nothing), so resuming from background does not refetch either. Unlike the match viewer, backing out and reopening does recover (initState re-runs the history query), but nothing tells the user the thread is incomplete while they are looking at it.

---

## 42. [MEDIUM] Deleting the last ball of an over from the ball log leaves the console unable to name the correct bowler
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:1100

**Failure scenario**

Bowler X completes over 1 (6 legal balls). `_afterBall` (line 41-53) stashes `_lastOverBowlerId = X` and clears `_bowlerId`. The scorer notices the 6th ball was recorded in error, opens the always-available Ball log action (line 338-342, `context.push`, so the console State stays alive underneath), and deletes that delivery. ball_log_screen.dart:203-204 invalidates `inningsDeliveriesProvider` + `inningsStateProvider`, so the console rebuilds showing 0.5 overs - the over is open again and it is still X's over. But `_bowlerId` is still null and `_lastOverBowlerId` is still X, so the pad is disabled and the bowler picker renders X as `enabled: false` with "Bowled last over" (line 1100, 1111-1115). The only selectable bowlers are the wrong ones: picking Y credits the 6th ball of X's over to Y (permanently, in the career stats re-fold). The only escape is to leave and re-enter the console so the State is recreated, which nothing tells the scorer.

**Why it is real**

`_undo` (line 1037) explicitly restores `_bowlerId` from `_lastOverBowlerId` for exactly this reason (see its doc comment), but the ball-log correction path performs the same state change to the innings and never touches the console's local fields. Undo is also unreachable in this situation because `_betweenBallRow` only renders in the not-ended branch and the ball log is the only correction surface for a completed over.

---

## 43. [MEDIUM] Expired discover posts still read as 'open' to their author, with no expiry shown and no way to renew
- **file**: `Projects/cricket-app/app/lib/src/features/discover/data/discover_providers.dart`:140

**Failure scenario**

A user posts 'Need 2 players, Sat 3pm'. 20260707160000_posts_expire.sql now sets expires_at = match_at + 1 day (or created_at + 14 days when undated) and discover_posts filters `expires_at > now()` plus `match_at >= now() - 6 hours`. On Sunday the post is invisible to every other user. The author opens My posts: myPostsProvider selects only 'id, mode, flair, title, status, created_at' - never expires_at or match_at - and my_posts_screen.dart renders a status Chip reading 'open' plus the Mark filled / Cancel actions. Nothing in the app ever reads or writes expires_at (grep: the composer never passes _expires_at, no screen displays it), so the author is told their ad is live, sees zero replies, and has no control to extend it. The only way to get back into the feed is to guess that the post died and create a new one.

**Why it is real**

Verified against both sides: the server-side filter exists and is unconditional (expires_at defaulting + the new match-date floor), while the client query at line 140 and the status chip in my_posts_screen.dart:79-82 have no notion of expiry. The expiry rule landed on 2026-07-27 with no client change, so the 'open' label is now wrong for any post past its date.

---

## 44. [MEDIUM] GPS lookup has no time limit - "Use my current location" spins forever on a real handset while returning instantly on the simulator
- **file**: `Projects/cricket-app/app/lib/src/features/discover/data/location_service.dart`:30

**Failure scenario**

`Geolocator.getCurrentPosition()` is called with no `LocationSettings`, hence no `timeLimit`, so it waits indefinitely for a fresh fix. A user indoors, in a stadium basement, on a cold-start GPS, or on an Android device where the fused provider has no cached fix taps "Use my current location" in LocationScreen (location_screen.dart:81) or the team home-base picker (team_page_screen.dart:669). `_busy` is set true, the button becomes a spinner and is disabled (location_screen.dart:105-116), and neither the `on LocationException` nor the generic `catch` ever runs because the future never completes. There is no cancel and no timeout, so the spinner runs until the screen is popped. On the iOS simulator, which serves a canned location immediately, this always returns in milliseconds - which is why every verification pass on the sim looked green.

**Why it is real**

geolocator's `getCurrentPosition` only bounds itself when `timeLimit` is supplied in `LocationSettings`; the call site passes nothing. The state machine around it (`_busy` toggled in the `finally`) is only reachable on completion or throw, so a hanging platform future leaves the UI pinned in the loading state permanently. The user can still fall back to the "Advanced: exact coordinates" fields, so this is a stuck control rather than a total dead end - but the primary, one-tap path to the app's headline geo feature silently never finishes.

---

## 45. [MEDIUM] JOURNEY D proves Swap strike had an effect but checks Undo only by the absence of an error toast, which a dead Undo also satisfies
- **file**: `Projects/cricket-app/app/integration_test/user_journeys_test.dart`:531

**Failure scenario**

Lines 508-511 state the rule explicitly ('Existing is not the same as working ... Prove the tap had an EFFECT') and lines 520-528 do exactly that for Swap strike by comparing the 'On strike:' line before and after. Undo gets `await tester.tap(...Undo); expect(find.textContaining('Could not undo'), findsNothing);` - no before/after score comparison. Re-wrap the pad in the AbsorbPointer that originally killed these controls, or make undoLastBall a no-op, and the assertion still passes: nothing happened, so no 'Could not undo' toast appears. The same journey also scores its two ordinary runs inside `if (b.evaluate().isNotEmpty)` (lines 488-499), so if the run pad were dead there would be nothing to undo and no step would notice.

**Why it is real**

'Undo' is the scorer's only escape from a mis-tap, and it is the control the AbsorbPointer regression is documented to have killed. The journey's Swap-strike assertion shows the team knows an error-absence check is insufficient; Undo was left on the weaker form.

---

## 46. [MEDIUM] Pasted tournament join codes are not sanitised the way team invite codes are, so a valid invite is reported as already used, or navigates to a non-existent route
- **file**: `Projects/cricket-app/app/lib/src/features/tournaments/presentation/tournaments_list_screen.dart`:119

**Failure scenario**

The organizer shares 'Add your team to my cricket tournament on Pitch: https://pitch.app/join-tournament/<token>\nOr enter this code in the app: <token>' (manage_tournament_screen.dart:377-381). The recipient copies the whole message and pastes it into Tournaments -> Join a tournament. _joinWithCode does `code.split('/join-tournament/').last.trim()`, which keeps everything after the token including the newline and the second sentence, so the token becomes '<token>\nOr enter this code in the app: <token>'. That still matches /join-tournament/:token as one URI segment, the screen loads, joinTournamentWithToken fails, and the user is told 'This invite has already been used or is no longer valid.' for an invite that is perfectly valid. If instead the pasted link carries a trailing slash, `.last` is empty, the guard at line 117 checked `code` (not `token`) so the empty token passes, and context.push('/join-tournament/') is normalised to '/join-tournament', which matches no route at all. The sibling team-invite parser handles both cases - inviteTokenFrom (my_teams_screen.dart:14-21) splits on [?#\s] and my_teams_screen.dart:62 re-checks the extracted token for emptiness.

**Why it is real**

Confirmed the guard order at tournaments_list_screen.dart:117-122 (checks `code`, then derives `token`, then navigates with no further validation) and confirmed with a Dart snippet that Uri.parse('/join-tournament/abc\nOr enter this code in the app: abc') yields a single percent-encoded path segment (so the screen loads with a junk token) while '/join-tournament/' normalises to the unmatched '/join-tournament' (go_router configuration.dart normalizeUri strips the trailing slash).

---

## 47. [MEDIUM] Raw PostgrestException / SocketException text is dumped into the scorer's SnackBar on every failed ball
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:110

**Failure scenario**

`_record`'s catch special-cases only the optimistic-concurrency message and otherwise calls `_toast(raw)` with `raw = '$e'`. Scenario: scoring was handed to a team-mate via transfer_scorer while this device still has the console open; `record_ball` raises 'not authorized' (20260707130700_bowler_cap_feasible.sql:63) and every subsequent tap on the run pad shows the user `PostgrestException(message: not authorized, code: P0001, details: , hint: null)`. Offline at the ground, the same button shows `ClientException with SocketException: Failed host lookup: 'ocejkqihgiinonpyafhl.supabase.co' ...`. The same raw dump reaches the user from `_finishMatch` (line 674), `_startSecondInnings` (line 724) and `_retire` (line 975), all `_toast('$e')` - i.e. finishing a match, starting the chase and retiring a batter. Any RLS rejection surfaces the literal string 'row-level security policy for table ...' this way.

**Why it is real**

`humanError()` exists precisely for this (its doc comment names the leak: 'PostgrestException(message: new row violates row-level security policy for table "team_members", code: 42501)') and is imported and used in this very file at lines 163, 1012 and 1055 - four sibling call sites in the same class were left interpolating the exception directly. humanError would have mapped these to 'You do not have permission to do that.' / 'No connection. Check your network and try again.'

---

## 48. [MEDIUM] Raw exception objects rendered into page bodies and SnackBars at eight sites, including the public player page
- **file**: `Projects/cricket-app/app/lib/src/features/stats/presentation/player_stats_screen.dart`:38

**Failure scenario**

The login-free, shareable `/player/:id` screen renders `Text('Could not load stats.\n$e')` in the middle of the page. A signed-out visitor opening a shared career link while `player_public_profile` is rejected or unreachable sees the full `PostgrestException(message: permission denied for table player_career_stats, code: 42501, details: ..., hint: null)` printed in the app. player_stats_screen.dart does not import human_error at all. Peer sites that also put raw exception text in front of the user: error_retry.dart:33 renders `Text('$detail')`, and `detail: e` is passed at discover_screen.dart:123 and profile_screen.dart:26 (so a feed/profile RLS failure prints the exception under the friendly line); plus the fallback branches 'Could not start the conversation: $raw' (dm_inbox_screen.dart:183), 'Could not open the conversation: $raw' (post_detail_screen.dart:70), 'Could not join: $raw' (invite_accept_screen.dart:49 and join_tournament_screen.dart:66), 'Could not send the request: $raw' (team_page_screen.dart:214) and 'Could not delete: $raw' (team_page_screen.dart:339).

**Why it is real**

human_error.dart's own doc comment states the rule this violates - raw '$e' 'leaks Postgres internals ... and reads to the user as a crash' - and 30+ call sites across the app already comply. These eight are the residue; each is a plain string interpolation of the caught object, verified by grep for `Text(...$e` and `$raw`.

---

## 49. [MEDIUM] The 'Propose a match' bridge silently drops the notification DM and the carried-over fixture date
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/start_match_screen.dart`:125

**Failure scenario**

The keystone discover->match flow: a captain taps 'Propose a match' on a team_seeking_opponent post, and after `createMatch` succeeds the app DMs the poster the proposal (lines 116-126). That whole block is wrapped in `catch (_) {/* non-fatal: the match is created regardless */}`. If `get_or_create_dm_thread` hits its rate limit ('too many new conversations' - a real guard the DM inbox handles explicitly), or the poster has blocked the caller, or the insert fails, the proposer is navigated on to the squad wizard with no indication whatsoever: they believe the opponent was told, the opponent never hears, and both sides wait. The adjacent block at line 113 swallows `updateMatchSchedule` the same way, so the date/time the user carried over from the post is silently discarded and the match shows no schedule. Same pattern with the same silence: location_screen.dart:70 (the home base + area name the user just typed is not persisted, so the feed re-centres elsewhere next launch) and create_team_screen.dart:66 (the logo chosen at team creation vanishes).

**Why it is real**

Each is a bare `catch (_)` around a write that carries user intent, with no SnackBar, no error state and no record that anything failed; the comments assert 'non-fatal' about the write, but the user-visible promise (the opponent was notified / the date is set / the ground is saved) is exactly what fails. The DM is the entire point of the bridge - MTCH-7's own comment at line 115 says 'notify the poster who was seeking an opponent'.

---

## 50. [MEDIUM] The no-ball secondary-kind regression lock copies the console's mapping into the test, so reverting the console to the plural spelling stays green
- **file**: `Projects/cricket-app/app/test/unit3_regression_test.dart`:19

**Failure scenario**

The test defines a local `String? map(String uiKey) => switch (uiKey) { 'off_bat' => 'off_bat', 'byes' => 'bye', 'leg_byes' => 'leg_bye', _ => null }` under a comment saying it 'mirrors _nbKindEnum in scoring_console_screen.dart', then asserts the local map's outputs are in the enum set. Change lib/src/features/scoring/presentation/scoring_console_screen.dart:1129-1134 back to emitting 'byes'/'leg_byes' (the shipped bug: every no-ball that went for byes was a hard Postgres 400 and could not be scored at all) and both tests in the group still pass, because neither ever calls _nbKindEnum. The second test ('the raw plural UI keys are NOT valid enum values') asserts only that the test's own const set lacks two strings - it cannot fail for any state of the app.

**Why it is real**

_nbKindEnum is a private static on a private class, so it is unreachable from the test as written; the duplication is what makes the lock decorative. The only remaining coverage is JOURNEY D in integration_test/user_journeys_test.dart, which needs a booted simulator and live Supabase - the widget suite that gates every commit has none.

---

## 51. [MEDIUM] The scoring console cannot record any dismissal off a wide or a no-ball
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:1335

**Failure scenario**

Batter is stumped off a wide (or run out off a no-ball) - both legal and common. The WICKET pad opens _wicket, whose final `_record(...)` call passes only runs/wicketType/dismissedId/incomingId/fielderId/crossed: there is no wide or no-ball control anywhere in the sheet. The Extras sheet (_extras, line 184) has no wicket control. So the scorer's only option is two separate taps: record the wide, then record the stumping as a second delivery. That second delivery is legal (`is_legal` = wides=0 and nb=0), so the fold adds a legal ball that was never bowled: the over runs to 7 balls, the bowler is charged an extra ball in his figures, `balls_remaining`/RRR in a chase are off by one, and if the illegal ball was a no-ball the wicket lands on the free hit and record_ball rejects anything except run_out/obstructing/hit_ball_twice.

**Why it is real**

record_ball explicitly enumerates which dismissals are legal on a wide and on a no-ball/free hit, so the backend is built for this event; the console has no path to produce it. _allWicketTypes/_freeHitWicketTypes (lines 1141-1146) and the sheet body (1208-1330) contain no extras controls, and _record is only ever called from the pad's run buttons, _extras, or _wicket - never with both a wicket and wides/noBall set.

---

## 52. [MEDIUM] Uploaded photos are never deleted from storage - a deleted user's profile picture and a deleted post's images stay publicly served forever
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260707130500_delete_account_always_anonymize.sql`:26

**Failure scenario**

A user uploads a profile photo (app/lib/src/features/identity/data/identity_repository.dart:39-52 puts it at avatars/<uid>/<micros>.jpg and returns getPublicUrl) and photos on a looking-for post (discover_repository.dart:25-30, post-images/<uid>/...). They delete their account: delete_my_account nulls profiles.photo_url and deletes their looking_for_posts rows, but nothing anywhere in the codebase ever calls storage.remove() or deletes from storage.objects - grep for 'storage' in app/lib/src returns only the two upload sites plus getPublicUrl. Both buckets are created with public = true (20260625140000:5, 20260617130100:5), and a public bucket serves /object/public/<bucket>/<path> WITHOUT consulting RLS - as the 20260707190100 migration itself notes. So the person's face, and every image from every post they ever deleted, remains fetchable by anyone holding or having cached the URL (the feed hands those URLs to every nearby user), after the account is gone. The same applies to every avatar they ever replaced, since uploads use a fresh timestamped path each time and the old object is never removed.

**Why it is real**

Confirmed by reading both bucket migrations (public = true, no lifecycle rule, only insert/select/delete policies), the storage-hardening migration's own statement that public buckets bypass RLS on read, delete_my_account's body (no storage statements), and an exhaustive grep of the Flutter source showing no delete/remove call against storage.

---

## 53. [MEDIUM] Winning margin in wickets is derived from squad size, so a squad larger than 11 reports the wrong result and needs more than 10 wickets to be all out
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707190000_did_not_bat_excludes_crease.sql`:199

**Failure scenario**

Team roster has 13 members and the scorer ticks all of them on the Squads screen (match_squads_screen.dart:_next only validates `a < 2 || b < 2`; there is no upper bound and no 11-player cap anywhere). `_innings_fold_params` sets squad_size = 13, so `all_out = 12`. The chasing side passes the target 5 wickets down: `_wkts_rem := _all_out - _wickets` = 12 - 5 = 7, and the fold returns `result_type = win_by_wickets, margin_wickets = 7`. The console's _resultLine renders 'X won by 7 wickets', and _finishMatch persists that exact sentence into matches.result.note, which is what the public viewer, the share card and match history display forever. The correct margin is 5. In the first innings the same squad means the innings does not close at 10 wickets - the fold keeps going until 12 fall, letting a 12th and 13th batter bat and producing a fall-of-wickets list with 11 and 12 entries.

**Why it is real**

all_out = squad_size - 1 is the right generalisation for small-sided games (9 named players -> all out at 8), but cricket caps it at 10 wickets regardless of how many players are named. Nothing clamps squad_size to 11: _innings_fold_params only floors it at 2 (`nullif(count(*), 1)` with `having count(*) >= 2`), and the squads UI has no maximum. add_squad_member happily accepts every roster member of a participating team.

---

## 54. [MEDIUM] add_match_guest's duplicate-name check ignores left_at, so a guest who was removed from a team can never be re-added under their real name from the match-setup wizard
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260703180100_match_guest_validation.sql`:23

**Failure scenario**

"Ravi" is a guest on Sunday XI who has played, so removing him leaves a tombstoned row (`leave_team`, 20260707180000:100 - guests take the tombstone branch because match_squad/deliveries reference the membership id). Weeks later the captain is setting up a new match and Ravi turns up. The squad picker cannot offer him: `teamMembersProvider` filters `.isFilter('left_at', null)` (app/lib/src/features/scoring/data/match_providers.dart:44). So the captain taps "Add guest player" and types "Ravi". `add_match_guest` runs:

  if exists (select 1 from public.team_members
             where team_id = _team_id and lower(guest_name) = lower(_name)) then
    raise exception 'a guest with this name is already on the team';

The tombstone matches, so the wizard shows "a guest with this name is already on the team" for a player who is demonstrably not on the roster and not in the picker. The only way forward is to invent a different spelling ("Ravi K"), which mints a second membership id and permanently splits his career stats, since player_key is COALESCE(profile_id, member_id) (20260623141000:13-17).

**Why it is real**

Its sibling `add_guest_member` had exactly this check and was repaired in 20260707200000_rejoin_after_leaving.sql:141-147, which added `and left_at is null` and states the motivation directly: "a guest who was removed could never be re-added under the name their team actually calls them." `add_match_guest` was written as a deliberate copy of the same guard (its own header at 20260703180100:1-3 says "same guard as add_guest_member") but the rejoin migration never touched it - grep for add_match_guest across migrations returns only 20260701180000 (original) and 20260703180100 (the validation revision), so the un-filtered check at line 23 is what is installed. tests/86-add-match-guest.test.sql exercises the duplicate case only against a live member.

---

## 55. [MEDIUM] anchorProvider survives sign-out, so the next signed-in user's feed and new posts are anchored to the previous user's city
- **file**: `Projects/cricket-app/app/lib/src/features/discover/data/discover_providers.dart`:41

**Failure scenario**

User A opens Discover -> "Near me" -> "Use my current location" (Delhi) -> Save. `location_screen.dart:55` writes that into `anchorProvider`. A signs out (profile_screen.dart:183). B signs in on the same device; B's saved home base is Mumbai. `DiscoverScreen.build` computes `effectiveAnchor(ref.watch(anchorProvider), ref.watch(homeLocationProvider).value)` (discover_screen.dart:43-46) and `effectiveAnchor` returns the explicit choice first (line 46-52), so B's feed is centred on Delhi. Nothing on screen shows the coordinates (the filter bar only has a "Near me" button). Worse, `NewPostComposer._post` uses the same anchor for `createPost(lat:..., lng:...)` (new_post_composer.dart:128-140), so every looking-for post B publishes is geotagged ~1100 km away: nobody near B ever sees it and B never sees local games, for the rest of the process lifetime.

**Why it is real**

`AnchorNotifier` deliberately has no dependencies (`build() => null`, line 33-34) so it is never invalidated by the session change, and `clear()` is called nowhere in `lib/` - `grep -rn anchorProvider lib test` shows the only `clear()` call is in test/anchor_home_test.dart:33. Every other user-scoped provider watches `currentSessionProvider` and resets; this one does not.

---

## 56. [MEDIUM] delete_match's tournament guard is bypassable - the matches table still grants DELETE to the client
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260616200501_matches_rls.sql`:13

**Failure scenario**

delete_match refuses to touch any match with a tournament_matches row because 'it is owned by the bracket and removing it would corrupt standings' (20260702130000:15-17). But `grant select, insert, update, delete on public.matches to authenticated` plus policy matches_delete_owner (owner_id = auth.uid()) is still in force, and every generated fixture is created with owner_id = the organizer (20260625150500:31, 20260625150700:32/37, 20260625150800:23). One PostgREST call - DELETE /rest/v1/matches?id=eq.<fixture_id> - by the organizer deletes a completed group fixture: innings, deliveries, match_squad and the tournament_matches row all cascade away. tournament_standings then recomputes without that result, so points, NRR and the qualifying two per group silently change on the public tournament page, and generate_playoffs seeds the wrong teams. No RPC guard is consulted.

**Why it is real**

The 20260707130100_revoke_direct_writes batch fixed exactly this pattern for tournament_teams, tournament_matches, matches UPDATE and tournament_invites, but its own comment at line 30-31 kept matches DELETE on the belief that 'delete_match fronts it' - which is not what a table-level grant means. Grep confirms no later migration revokes DELETE on public.matches or narrows matches_delete_owner, so the RPC's tournament check is decorative.

---

## 57. [MEDIUM] delete_my_account converts the deleted person's memberships into claimable guest rows, letting another user absorb their entire career record
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707130500_delete_account_always_anonymize.sql`:40

**Failure scenario**

Bob deletes his account. Step 2 runs `update team_members set profile_id = null, guest_name = coalesce(guest_name, 'Deleted user') where profile_id = _me`, leaving left_at NULL. Those rows now satisfy request_guest_claim's only gate - `guest_name is not null and profile_id is null` (20260615141401_rpc_guest_claims.sql lines 16-21) - and they still appear on the roster, where team_page_screen.dart line 146 renders a "This is me" button for every row with profile_id == null to any signed-in, non-anonymous viewer. Mallory taps it on the "Deleted user" row; the captain sees "Mallory says they are Deleted user - review the claim" and approves. approve_guest_claim sets profile_id = Mallory on Bob's membership row. Because v_player_key computes player_key = coalesce(profile_id, member_id) (20260623141000_player_views.sql line 15) and every deliveries actor column references team_members(id), Bob's whole playing history - every innings, wicket, catch, POTM contribution - re-keys onto Mallory's public profile at read time with no backfill, and Mallory's career stats page now shows Bob's record as her own.

**Why it is real**

The three pieces are all live and unguarded: delete_my_account does not set left_at and does not mark the row unclaimable; request_guest_claim's only test is guest_name-not-null/profile_id-null, which the anonymised row now passes; approve_guest_claim's guards check only "is there a pending claim" and "is the claimer already a member", neither of which excludes a deleted-account row. The migration header states the intent is that "opponents' scorecards keep referring to an inert 'Deleted user' row" - the row is not inert, it is claimable. This is reachable entirely through sanctioned UI (roster claim button + captain approval), no direct RPC needed.

---

## 58. [MEDIUM] discover_posts returns every open post in the radius with no LIMIT and the feed has no pagination
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707160000_posts_expire.sql`:88

**Failure scenario**

The current discover_posts definition ends at `order by (p.match_at is not null and p.match_at < now()), p.geog_coarse <-> probe` with no LIMIT and no offset/cursor parameter, and the caller-supplied radius is clamped up to 50 km. DiscoverScreen renders whatever comes back into a single ListView (discover_screen.dart:131-136) with no lazy paging. In a dense city at the default 25 km anchor, once the app has a few thousand live posts, every Discover open transfers all of them - including each post's full `description` and `image_urls` array - over mobile data before a single card appears. The headline screen becomes the slowest one in the app precisely as the product succeeds, and the RefreshIndicator re-pays the whole cost on each pull.

**Why it is real**

Read the latest definition (20260707160000 supersedes 20260707130600) and confirmed no LIMIT clause and no pagination parameter in the signature; read the screen and confirmed a single unpaged ListView over `posts.length`. An earlier fix (20260707170100_search_opponent_teams.sql) applied exactly this reasoning - 'the screen's cost no longer grows with the size of the database' - to the opponent picker but not to the feed itself.

---

## 59. [MEDIUM] insert_ball's seq renumber fires two realtime broadcasts per shifted delivery - a single mid-innings correction storms every viewer with hundreds of full re-folds
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260705120100_corrections_apply_guard.sql`:53

**Failure scenario**

Scorer notices a ball was missed at over 3 of a 20-over innings and uses Ball log > 'Insert a ball after this'. insert_ball renumbers with the two-step negation: `update deliveries set seq = -(seq+1) where seq > _after_seq` then `update deliveries set seq = -seq where seq < 0` (lines 53-54). `deliveries_broadcast` is AFTER INSERT OR UPDATE OR DELETE FOR EACH ROW with no WHEN clause and no column list (20260616202201_broadcast.sql:23-24), so with ~110 rows after the insertion point that is ~220 realtime.messages inserts on match:<id> in one transaction, plus the insert itself. Every connected viewer runs `_refold()` per message, and each _refold issues one matchProvider fetch + one matchInningsListProvider fetch + one compute_innings_state RPC per innings (match_viewer_screen.dart:103-107) - roughly 880 HTTP round-trips per viewer, each re-folding the whole 130-row innings, for one inserted ball. With 20 viewers that is ~17k requests and 17k full folds; the channel can also blow through the realtime message-rate budget and get dropped, which under finding #2 means those viewers never recover.

**Why it is real**

The fix that addressed this class (20260707140000_restamp_no_op_writes.sql) names the problem in its own header - 'insert_ball was worse (renumber + restamp = ~235)' - but only changed restamp_innings_strike to skip no-op writes. The renumber UPDATEs are untouched and still unconditional, and they are inherently non-no-op (every shifted row really does change seq twice). No WHEN clause was added to deliveries_broadcast and no column filter exists, so a pure seq bookkeeping change is indistinguishable from a scoring change to every subscriber.

---

## 60. [MEDIUM] matches has no index on team_a_id or team_b_id, so every team-scoped match query is a full table scan
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260616200301_matches.sql`:21

**Failure scenario**

public.matches indexes only scorer_id and owner_id, yet three hot paths filter on the team columns: (1) teamMatchesProvider does `.or('team_a_id.eq.$teamId,team_b_id.eq.$teamId')` then orders by created_at and limits 15 (identity_providers.dart:105-111) - the limit does not help because the whole table must be scanned and sorted first; (2) team_career_stats does `where status='complete' and _team_id in (team_a_id, team_b_id)` (20260703190000_rpc_team_career_stats.sql:7-8), anon-granted; (3) search_opponent_teams' `played` CTE does `where m.team_a_id in (select team_id from mine) or m.team_b_id in (select team_id from mine)` (20260707170100:34-35), which runs on every open of Start-a-match. Opening any team page at 500k matches performs two full scans of matches (record line + recent matches), and the Start-a-match opponent picker performs a third - so the fix that was applied to bound the opponent list still leaves an unbounded scan underneath it.

**Why it is real**

Confirmed the DDL creates only matches_scorer_idx and matches_owner_idx, and confirmed by grep that no later migration adds a team-column index. Read all three query sites. An OR across two columns needs either two indexes with a bitmap-or or an expression index; neither exists.

---

## 61. [MEDIUM] matches.status is stuck at 'innings_break' if a correction reopens the first innings
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:584

**Failure scenario**

First innings ends (all out / overs done). `_endPanel` writes the break once via the `_breakMarked` one-shot (line 584-588), so `matches.status = 'innings_break'`. The scorer then opens the Ball log (still reachable from the app bar) and deletes the wrong final wicket ball; `inningsStateProvider` re-folds to `in_progress`, the console shows the run pad again and scoring resumes. But nothing ever writes the status back: `mark_innings_break` only fires on `status = 'live'` (backend/supabase/migrations/20260706111300_innings_break_status.sql) and `'innings_break' -> 'live'` happens only inside `start_innings` (20260706111400). `_breakMarked` also stays true forever, so the console will not re-evaluate. Result: for the remainder of the first innings every viewer sees no LIVE badge (`live = match['status'] == 'live' && ...`, match_viewer_screen.dart:529), the Watch-live list labels the game "innings break" (live_matches_screen.dart:48), and the Matches tile says "Innings break" (matches_screen.dart:130) while balls are being recorded.

**Why it is real**

The status write is a one-way latch in both the client (`_breakMarked` is never reset) and the backend (no RPC moves `innings_break` back to `live` other than creating a second innings), yet the innings state that triggered it is fully reversible from the corrections screen that the same console links to.

---

## 62. [MEDIUM] photo_url / image_urls / logo_url are unvalidated client-supplied strings rendered with NetworkImage, so any profile is a tracking pixel that harvests every viewer's IP - including logged-out viewers of the public /player, /watch and /tournament pages
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260615140201_profiles.sql`:5

**Failure scenario**

Attacker creates a normal account, then PATCHes their own row: PATCH /rest/v1/profiles?id=eq.<self> {"photo_url":"https://attacker.example/p.png?v=<self>"}. profiles_update_own (20260615140301_profiles_rls.sql:18-22) permits it and profiles.photo_url has no CHECK constraint, no format validation, and no host allowlist anywhere in the schema or in IdentityRepository.updateMyProfile (app/lib/.../identity_repository.dart:23-35, which passes the field straight through). The attacker joins a public match squad or a tournament. From then on every screen that draws them calls InitialsAvatar -> NetworkImage(photoUrl!) (app/lib/src/features/identity/presentation/initials_avatar.dart:26) - team roster, DM inbox, search results, claim inbox, leaderboards, the player-stats header - and each render issues an unauthenticated GET to attacker.example, handing over the viewer's IP address (hence coarse real-world location and ISP), User-Agent, and a timestamped read receipt of exactly who looked. Because public_profile_minimal (20260617122500) and player_public_profile (20260623144000) return photo_url and are granted to anon, and /player/:id, /watch/:id and /tournament/:id bypass the auth gate (app/lib/src/core/routing/app_router.dart:65-70), the beacon also fires for logged-out visitors who have no account and never consented to anything. The same hole exists on looking_for_posts.image_urls - create_looking_for_post takes _image_urls text[] verbatim (20260707160000_posts_expire.sql:34-42) and post_detail_screen.dart:158 does Image.network(url) on each - and on teams.logo_url, which any team admin sets via a raw table UPDATE (identity_repository.dart:59) and which anon can read through teams_select_anon.

**Why it is real**

I checked for validation on all four columns: grep over every migration for a CHECK/LIKE/regex touching photo_url, logo_url, link_url or image_urls returns nothing, and the profiles table definition (line 5) is a bare `photo_url text`. The write paths are raw table updates and an RPC that inserts the array unmodified, so nothing constrains the host to the project's storage domain even though the app's own uploaders always produce a getPublicUrl (identity_repository.dart:39-52, discover_repository.dart:18-31). The renderers are unconditional: InitialsAvatar has no scheme/host check, and post_detail_screen.dart:158 wraps the raw string in Image.network. The anon reachability is real - public_profile_minimal's grant on line 14 includes anon and it selects photo_url on line 8. Nothing in the two prior reviews touches URL provenance (no mention of tracking pixels, IP addresses, or URL validation in any of the review docs).

---

## 63. [MEDIUM] post_replies is globally readable and post_detail is ungated, so any account can dump every reply body in the database and resolve every post to a name and a place label regardless of radius, status or expiry
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260616203501_post_replies.sql`:11

**Failure scenario**

Step 1: GET /rest/v1/post_replies?select=post_id,author_id,body,created_at (paginate with Range). post_replies_select_authenticated is `using (true)` with a table-wide SELECT grant, so this returns every reply ever written by anyone to any post anywhere - the free-text field where people actually type "I'm in, ring me on 98xxxxxxxx", "we play behind the Shivaji Park gate at 6.30", "can't make it, I'm out of town till the 20th" - each joined to its author_id. Step 2: for each post_id, POST /rest/v1/rpc/post_detail. post_detail (20260702170100:6-17) is SECURITY DEFINER with a bare `where p.id = _post_id` - no distance check, no status check, no expires_at check, no author check - and returns title, description, place_label, match_at, the author's display_name and the team name. The result is a global, permanent index of who is looking for a game, roughly where, and with whom, harvested by a caller who is nowhere near any of them. That defeats every containment the feed applies: discover_posts clamps the radius to at most 50 km, requires status='open', drops expired posts and drops matches older than 6 hours (20260707160000_posts_expire.sql:66,76-86), and SEC-2 deliberately revoked the blanket read on looking_for_posts so that only the RPCs answer for it (20260702170000_looking_for_posts_hide_geog.sql:7-11).

**Why it is real**

Both statements are the live definitions. post_replies_select_authenticated at line 11 is `for select to authenticated using (true)` on top of `grant select, insert, delete ... to authenticated` at line 10, and no later migration drops or replaces it (grep for post_replies across all migrations returns only this file, the notify trigger, and the delete_account discussion). post_detail's body is four lines long and I read all of it - the WHERE clause has exactly one predicate. The asymmetry is what makes it a defect rather than a design choice: the same fix run that hid geog and put post reads behind definer RPCs left the replies table and the by-id resolver wide open, so the side door survived the front-door lock. The prior reviews mention post_replies only inside a recommendation about anonymous sessions; the global scope for ordinary real accounts, and post_detail's missing gate, are not reported anywhere.

---

## 64. [MEDIUM] searchProvider fires per keystroke and is not autoDispose, so every prefix result (and every failure) is retained for the session
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/discover/data/discover_providers.dart`:124

**Failure scenario**

SearchScreen does `onChanged: (v) => setState(() => _query = v)` (search_screen.dart:57) and the build watches `searchProvider(_query)` (line 32); the DM people-picker does the same (dm_inbox_screen.dart:200,228). searchProvider is a plain `FutureProvider.family` - in riverpod 3.3.2 FutureProvider defaults to `isAutoDispose = false` (verified in the package source, providers/future_provider.dart:107). So each distinct prefix creates a provider element that is never disposed: typing and clearing a few names leaves dozens of cached result lists alive for the whole session, and - the user-visible half - a query that failed on a dropped connection stays cached as an error forever, so retyping the exact same name never retries and the user is stuck on 'Search failed.' until they restart the app.

**Why it is real**

This is the identical defect that was already found and fixed for opponentSearchProvider, which carries an explicit comment saying so ('autoDispose: the family is keyed per KEYSTROKE ... a search that failed on a dropped connection stays cached as a failure, so retyping the same name never retries', match_providers.dart:22-33). searchProvider, the other keystroke-keyed family with two call sites, was left non-autoDispose - the class of bug was fixed at one instance only.

---

## 65. [MEDIUM] tournament_leaderboard materialises the entire team_members x profiles join on every public tournament page load
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260625150900_rpc_tournament_leaderboard.sql`:27

**Failure scenario**

The `names` CTE is `select tmem.id mid, coalesce(tmem.guest_name, p.display_name, 'Player') name from public.team_members tmem left join public.profiles p on p.id = tmem.profile_id` - unfiltered, the whole membership table joined to the whole profile table. It is referenced five times (lines 36, 38, 40, 42, 44), and PostgreSQL only inlines a non-recursive CTE that is referenced exactly once, so this one is materialised. Every load of any public tournament page therefore builds a temporary relation containing one row per team membership in the entire database, just to attach names to at most 50 leaderboard rows. At 500k memberships this spills to disk (work_mem is small on hosted Supabase) on an anon-callable endpoint.

**Why it is real**

Read the CTE and counted its five references; the reference count is what forces materialisation under the PG12+ inlining rule. The five aggregates it joins against are each already capped at `limit 10`, so the correct shape is a join to team_members keyed by those <=50 ids - the unfiltered CTE is pure overhead whose size tracks total platform membership.

---

## 66. [MEDIUM] tournament_overview folds every innings of the tournament three separate times per page load
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260702150200_overview_fixture_scores.sql`:32

**Failure scenario**

One tournament_overview call runs (a) `cross join lateral (select public.compute_innings_state(i.id))` for every innings of every fixture (line 32), (b) public.tournament_standings (line 18), which independently runs compute_innings_state over every group-stage innings (20260702150100_standings_seed_all_teams.sql:25-30), and (c) public.tournament_leaderboard (line 44), which runs compute_innings_cards over every complete innings (20260625150900:13). For a 16-team tournament - 24 group matches plus 3 playoffs, ~54 innings - that is ~156 invocations of a plpgsql loop that reads up to 120 delivery rows each and rebuilds jsonb accumulators with jsonb_set per ball, roughly 19,000 loop iterations of jsonb churn. The RPC is granted to anon and the page is login-free with no caching layer, so the organiser sharing the bracket link on WhatsApp during the final has every recipient triggering that work; the page takes seconds and eventually exceeds the statement timeout, at which point the public tournament page shows only an error.

**Why it is real**

Traced all three call sites in the current definition and confirmed each recomputes the same folds from raw deliveries - there is no materialised innings summary, and nothing memoises compute_innings_state across the three branches within a single call. compute_innings_state and compute_innings_cards are the full O(deliveries) loops in 20260707130000_fold_lockstep_params.sql.

---

## 67. [MEDIUM] tournament_standings computes NRR overs with a hardcoded /6.0, ignoring matches.balls_per_over, so the group ladder mis-ranks any non-six-ball-over match
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260702150100_standings_seed_all_teams.sql`:34

**Failure scenario**

An organizer creates a tournament with 10 overs of 8 balls (create_tournament accepts _balls_per_over with no validation, 20260625150300 line 3; matches_balls_per_over_sane permits 1..12, 20260707170000 line 27; generate_group_fixtures propagates _t.balls_per_over into every fixture, 20260625150500 line 32). Team A bats out its full quota: 80 legal balls for 120 runs. compute_innings_state correctly reports 10.0 overs (it divides by _bpo from _innings_fold_params). tournament_standings instead computes ofv = legal_balls / 6.0 = 13.33 overs, so A's for-rate is 120/13.33 = 9.0 instead of 12.0 - a 33% deflation. The same distortion is applied asymmetrically: any innings that ended all-out uses the `overs_limit` branch (a true over count, 10), while any innings that batted out its overs uses the /6.0 branch, so two teams with identical real performance get different NRRs depending only on how their innings ended. Group ranking is `order by points desc, nrr desc`, so teams qualify for the playoffs in the wrong order.

**Why it is real**

20260701130000_fold_v11_bpo.sql (SCOR-23) exists precisely to remove hardcoded /6 and %6 from the folds - it was applied to compute_innings_state/cards/restamp but not to the two derived readers. grep for hardcoded 6 shows exactly two live sites left: standings_seed_all_teams.sql lines 34 and 41 (NRR), and player_career_stats.sql lines 100 and 114 (career economy and the 'overs' display string, same root, same wrongness for bpo != 6). Both mix the /6.0 result with genuine over counts (overs_limit) in the same expression, so the two branches of the CASE are not even in the same unit.

---

## 68. [LOW] 'Share image' can fail with no message: the capture path has no catch and two silent early returns
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/match_viewer_screen.dart`:274

**Failure scenario**

`_captureAndShare` is wired straight to `onPressed` in both share sheets. It returns silently if `boundary == null` or `bytes == null`, and nothing in it is wrapped in try/catch, so a throw from `boundary.toImage(pixelRatio: 3)` (the full-scorecard card is arbitrarily tall - a two-innings card at 3x can exceed the platform's max texture/decode size), `image.toByteData`, or `File(...).writeAsBytes` (no space left on device) is an unhandled async error. The user taps 'Share image' on the scorecard they wanted to post to the team group and absolutely nothing happens, with no explanation and no second cue to try.

**Why it is real**

The two enclosing methods were already fixed for precisely this symptom - the catch at line 174 carries the comment 'a share tap that does NOTHING reads as a dead button - say why instead' - but the method that actually performs the capture and the file write was left with no handler and with unreported early returns.

---

## 69. [LOW] 'exposes penalty, overthrow and expectedLastSeq' asserts a constructor tearoff is non-null and checks none of those parameters
- **file**: `Projects/cricket-app/app/test/unit3_regression_test.dart`:44

**Failure scenario**

The whole test body is `const sig = MatchRepository.new; expect(sig, isNotNull);`. A constructor tearoff is never null, and MatchRepository.new is the CONSTRUCTOR while penalty/isOverthrow/expectedLastSeq are named parameters of recordBall. Delete every one of those parameters from MatchRepository and this assertion still passes; it would fail only if the class stopped existing, in which case the file would not compile.

**Why it is real**

The test names a contract (SCOR-7 full extras + SCOR-24 stale-write fence) and verifies nothing about it. It is a green check that reads as coverage in a suite whose whole purpose is regression locking.

---

## 70. [LOW] A failed home-location read silently pins Discover and every new post to the hardcoded Mumbai fallback for the session
- **file**: `Projects/cricket-app/app/lib/src/features/discover/data/discover_providers.dart`:57

**Failure scenario**

A user in Delhi (home base saved) cold-starts the app with no connectivity, or the `my_home_location` RPC fails past the retry budget. `homeLocationProvider` settles as AsyncError. `DiscoverScreen` reads it as `.value` (discover_screen.dart:45), which is null for an error, so `effectiveAnchor` silently returns `kFallbackAnchor` = (19.07, 72.87), Mumbai (line 29, 46-52). Connectivity returns; the feed's Retry button invalidates only `discoverFeedProvider(query)` (discover_screen.dart:124), so the query keeps the Mumbai anchor and the user is shown Mumbai games with no indication. If they then compose a post, `_post` uses the same anchor (new_post_composer.dart:128-140) and publishes it geotagged to Mumbai. Nothing recovers this except manually reopening Location and re-saving.

**Why it is real**

`homeLocationProvider` is a non-autoDispose FutureProvider whose only invalidation site is location_screen.dart:69, and both consumers read it through `.value`, which collapses error and "not set" into the same silent fallback. No screen surfaces the error and no retry path re-fetches it.

---

## 71. [LOW] Approving a guest claim does not refresh the team roster, so the team page keeps showing the guest row with "This is me"
- **file**: `Projects/cricket-app/app/lib/src/features/teams/presentation/claim_inbox_screen.dart`:30

**Failure scenario**

A captain visits their team page (caching `teamRosterProvider(teamId)`), then goes Profile -> My teams -> Claim requests and approves a claim. `_approve` invalidates only `claimInboxProvider` (line 30). `approve_guest_claim` transfers the membership to the claimer's profile, but the cached roster still has `profile_id: null` and `guest_name`, so returning to the team page shows the player as a Guest, still offers the "This is me" claim button (team_page_screen.dart:146-148, _MemberTile line 580-582), and still routes their row to the guest career page `/player/guest/:memberId` instead of their real profile (line 151-157). The team page has no pull-to-refresh, so this persists for the session.

**Why it is real**

`teamRosterProvider` is a non-autoDispose family (identity_providers.dart:52) and every other roster-mutating action invalidates it (team_page_screen.dart:313, 422, 480, 773); the claim-approval path - which also changes a `team_members` row - does not.

---

## 72. [LOW] Byes and leg-byes off a no-ball are bucketed as byes/leg-byes and not charged to the bowler
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707190000_did_not_bat_excludes_crease.sql`:84

**Failure scenario**

No-ball, keeper misses, batters run 2. The Extras sheet records type 'no_ball', 'The runs came from' = Byes, runs = 2, which sends extra_no_ball_penalty = 1 and extra_byes = 2 (scoring_console_screen.dart:303-312). The fold computes `_dconc := runs_off_bat + extra_wides + extra_no_ball_penalty` = 1, so the bowler is charged 1 run and his economy is computed off 1; by the Laws all 3 runs are No-ball extras debited to the bowler. The viewer's extras line then reads 'nb 1, b 2' instead of 'nb 3' (match_viewer_screen.dart:834-836), i.e. the scorecard claims byes were scored off a delivery from which byes cannot be scored.

**Why it is real**

Law 21.13 / Law 23-24: byes and leg-byes cannot be scored off a No ball - every run that is not off the bat is credited as a No ball, and No balls are debited to the bowler. `_dconc` deliberately excludes extra_byes and extra_leg_byes (correct for a legal delivery, wrong when extra_no_ball_penalty > 0), and the extras aggregation adds them to `_byes`/`_lb` unconditionally. The innings total is unaffected, but the bowler's runs conceded and economy are understated and the extras breakdown is wrong.

---

## 73. [LOW] Claim inbox evaluates is_team_admin per row across every pending claim in the database
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260615141301_guest_claims.sql`:19

**Failure scenario**

claimInboxProvider queries `from('guest_claim_requests').select(...).eq('status','pending').neq('requested_by', me)` (identity_providers.dart:33-48) with no team filter - scoping is left entirely to RLS. The policy is `requested_by = auth.uid() or public.is_team_admin((select team_id from team_members where id = membership_id))`. There is no index on guest_claim_requests(status), so the planner seq-scans the table, and for every pending row that survives the status filter it runs a correlated subquery plus a SECURITY DEFINER function call. Note also that the first branch uses bare `auth.uid()` rather than `(select auth.uid())`, so unlike the newer policies in this codebase it is re-evaluated per row instead of being hoisted to an InitPlan. A captain with two pending claims opens the inbox and the server performs one is_team_admin call for every pending claim anyone on the platform has ever filed; past a few hundred thousand rows the screen times out and the captain can no longer approve anyone.

**Why it is real**

Read the policy, the table DDL (no status index, only the pk and the unique(membership_id, requested_by)), the helper (20260615140601_authz_helpers.sql:16-29, an EXISTS over team_members), and the client query. Compare 20260703190100_team_join_requests.sql:20, which wraps auth.uid() in a subselect - the guest-claims policy predates that convention and was never updated.

---

## 74. [LOW] DM thread loads its full message history with no limit or pagination
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/messages/presentation/dm_thread_screen.dart`:52

**Failure scenario**

_init does `from('dm_messages').select('id, sender_id, body, created_at').eq('thread_id', ...).order('created_at', ascending:true)` with no limit, and _retryLoad repeats it in full. Opening a long-running conversation with a regular opponent (a few thousand messages accumulated over a season) downloads the whole transcript and pushes every row into `_messages` before the first bubble renders, then jumps to the bottom - so the user waits on a payload they will never scroll to. On a flaky connection the retry path pays the same cost again from zero.

**Why it is real**

Read the query: no `.limit()`, no cursor, and dmThreadMessagesProvider (discover_providers.dart:154-158) has the same shape. The supporting index dm_messages_thread_idx(thread_id, created_at) exists, so the DB side is fine - the defect is purely that the client asks for all of it with no way to page backwards.

---

## 75. [LOW] GoRouter has no errorBuilder/onException and the app has no '/' route, so go_router's default Page Not Found screen offers a Home button that does nothing
- **file**: `Projects/cricket-app/app/lib/src/core/routing/app_router.dart`:125

**Failure scenario**

Any location that matches no route falls back to go_router's built-in MaterialErrorScreen (the app runs MaterialApp.router, app.dart:23), which renders the raw exception text 'no routes for location: ...' and a single 'Home' TextButton wired to context.go('/'). The route table declares /splash, /watch/:matchId, /player/..., /invite/:token, /join-tournament/:token, /tournament/:id, /sign-in, /onboarding/create-profile and the three shell branches - there is no '/' route, so that button re-enters the same error screen. Reachable today via the empty-token paste described in the tournaments_list_screen finding (pushed, so back still works, but the user sees a raw exception and a dead Home button); reachable as an unrecoverable full-screen dead end as soon as anything arrives as a platform route rather than a push - Android deep linking is on by default (FlutterActivityLaunchConfigs.deepLinkEnabled returns true when the meta-data key is absent, and AndroidManifest.xml declares no flutter_deeplinking_enabled), the manifest registers a VIEW filter for io.supabase.pitch://login-callback, and such a URL normalises to path '/', which is a NavigatingType.go and therefore replaces the whole stack.

**Why it is real**

Read go_router 17.3.0's sources: configuration.findMatch returns an error match list for an unmatched URI, builder.dart:207 replaces the entire page stack with the error page for a go-type navigation, and pages/material.dart:50-53 hard-codes onPressed: () => context.go('/'). app_router.dart:125-133 passes no errorBuilder, errorPageBuilder or onException, and routes.dart declares no '/' path.

---

## 76. [LOW] Handing over scoring leaves the old scorer's Matches list offering a "Continue scoring" action that is denied on every tap
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/transfer_scorer_screen.dart`:33

**Failure scenario**

Scorer A uses the console's "Hand over scoring" and picks B. `_hand` (line 27-48) awaits `transferScorer`, shows a snackbar and pops twice, landing A back on the Matches list - but invalidates nothing. `myMatchesProvider` (`eq('scorer_id', me)`, match_providers.dart:224) still holds the pre-transfer rows, so the match is still listed under Live with the "Continue scoring" item and a tap target that pushes `Routes.scoreMatch(id)` (matches_screen.dart:147, 158-164). A opens it and every action - a run tap, Undo, swap strike - fails with the raw `not authorized` error from `record_ball` surfaced through `_toast(raw)` (scoring_console_screen.dart:110). Only a manual pull-to-refresh removes the row.

**Why it is real**

`myMatchesProvider` is non-autoDispose and is invalidated after every other match write (start_match_screen.dart:128, matches_screen.dart:234, scoring_console_screen.dart:662) but not after the one write that changes `scorer_id`, which is exactly the field the query filters on.

---

## 77. [LOW] Innings-break status write is swallowed and latched off, so viewers keep seeing 'Live now' at the break
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:587

**Failure scenario**

When the first innings ends, `_endPanel` fires `_repo.markInningsBreak(...)` once, guarded by `_breakMarked = true` set BEFORE the call, and ends with `.catchError((_) {})`. If that RPC fails (the connection blip that is most likely exactly at the interval, when phones come out of pockets), the flag is already latched, so it is never retried for the life of the widget, and nothing is shown to the scorer. The match row stays `status = 'live'`, so the public viewer, the Watch-live list and the Matches list all keep saying 'Live now' through the whole break while the console privately shows 'Innings break'.

**Why it is real**

`_breakMarked` is set before the await and never reset on failure, and the catchError callback has an empty body, so there is neither a retry nor any feedback. The comment calls it 'purely presentational state', but SCOR-1's own comment three lines above says the point of the write is that 'viewers/lists show "innings break" instead of "live"' - i.e. it is the only thing that keeps the public status honest.

---

## 78. [LOW] Scoring console dumps raw exception text when a ball fails to record - the one write path in the file that skips humanError()
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:110

**Failure scenario**

The scorer is at a ground with patchy signal and taps '4'. The RPC throws a ClientException/SocketException. `_record`'s catch only special-cases the concurrency-fence string; everything else goes to `_toast(raw)` at line 110, so the scorer sees a SnackBar reading `ClientException with SocketException: Failed host lookup: 'ocejkqihgiinonpyafhl.supabase.co' (OS Error: nodename nor servname provided, or not known, errno = 8)`. The same raw path is used by _finishMatch (line 674), _startSecondInnings (line 724) and _retire (line 974), so a flaky connection at the moment the match is being finished shows a Postgres/socket dump instead of 'No connection. Check your network and try again.'

**Why it is real**

core/ui/human_error.dart exists precisely for this (its header documents the 19 raw-'$e' sites the review found) and maps SocketException/ClientException/timeout to a human sentence. The same file already uses it for the wagon save (line 163), swap strike (line 1012), undo (line 1055) and the load-error state (line 385) - the four sites left raw are the primary write paths, including the one the scorer taps ~250 times per match.

---

## 79. [LOW] The '+5 penalty runs' switch always awards the 5 runs to the batting side, including for the case its own subtitle names
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:271

**Failure scenario**

The striker deliberately runs short. The umpire awards 5 penalty runs to the FIELDING side. The scorer opens Extras, sees the switch '+5 penalty runs on this ball' whose subtitle reads 'Ball hit a helmet, deliberate short run, etc.', and turns it on. `_extras` sets `pen = 5` and every branch passes it as `penalty: pen` -> extra_penalty = 5 on the delivery, and the fold adds extra_penalty into `_runs` and `extras.penalty` for the BATTING innings. The batting side gains the 5 runs it was penalised, a 10-run swing in the score, and in a chase it also moves runs_required/RRR and can hand the batting side a win it did not earn.

**Why it is real**

deliveries has a single extra_penalty column that only ever accrues to the innings being folded (`_pen := _pen + d.extra_penalty`, `_runs := _runs + _d_total`); there is no representation for penalty runs awarded against the batting side. The UI's own help text tells the scorer to use it for a deliberate short run, which is a penalty to the fielding side, so the wrong side is credited by following the instruction as written.

---

## 80. [LOW] The `crossed` flag is collected for 'obstructing the field' but the fold only applies it to run_out, so strike is wrong for the rest of the innings
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707190000_did_not_bat_excludes_crease.sql`:122

**Failure scenario**

Batters run, cross, and the non-striker is given out obstructing the field. The console's wicket sheet treats obstructing exactly like a run out - `_needsCrossedRuns(t) => t == 'run_out' || t == 'obstructing'` (line 1152) shows the 'Batters had crossed' switch and passes `crossed: true` to record_ball, which stores it. The fold's crossing swap is gated on `_is_wkt and d.wicket_type = 'run_out' and coalesce(d.crossed, false)`, so for 'obstructing' the swap never happens: the surviving batter is left at the wrong end, the incoming batter is inserted at the wrong end, and because strike is derived cumulatively from the opening pair every subsequent ball is credited to the wrong batter for the remainder of the innings (and restamp_innings_strike, which has the identical `= 'run_out'` gate, re-stamps the same wrong pairs onto every stored delivery).

**Why it is real**

All three folds (compute_innings_state line 122, compute_innings_cards, restamp_innings_strike) gate the crossing swap on `wicket_type = 'run_out'` only, while the UI collects and sends `crossed` for obstructing as well. The data is written and then silently ignored, so the scorer's correct input produces a wrong derivation with no error.

---

## 81. [LOW] The location-oracle assertions in test 110 all pass when discover_posts returns nothing, and one compares an expression to itself
- **file**: `Projects/cricket-app/backend/supabase/tests/110-unit2-oracle-and-cap.test.sql`:24

**Failure scenario**

Assertion 2 compares `count(*) from discover_posts(19.076123, 72.877654, 1) where post_id = _p` with the same count at radius 2000: if a regression stopped the fresh post being returned at all (radius/expiry/match-date floor, the exact class of bug test 112 exists for), both counts are 0 and 'a 1 m probe is indistinguishable from a 2 km probe (radius clamped)' passes with the radius clamp gone. Assertions 3 and 4 read approx_m for the post; with no row both sides are NULL, and `is(null, null)` and `is not distinct from` both pass. Nothing in the file asserts the post IS visible - unlike 112-posts-expire.test.sql:70-73, which pins `count = 1` as a positive control before asserting zeros. Assertion 3 is additionally a literal tautology: lines 34 and 35 are the identical `select approx_m from public.discover_posts(19.0761, 72.8776, 25000) where post_id = :'_p'` on both sides of is(), so it holds for any implementation of a deterministic function.

**Why it is real**

Three of this file's six assertions are the privacy guarantee for a geo app (a precise-location oracle), and all three degrade to vacuous truth on the one failure mode - an empty result set - that a discovery-query regression would produce.

---

## 82. [LOW] Toss screen's blocking error tells the scorer to tap an 'Edit squads' control that does not exist
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/toss_openers_screen.dart`:203

**Failure scenario**

When the bowling side has fewer than two squad members, `_start` refuses with 'The bowling side needs at least 2 squad members. Tap Edit squads below to add them.' There is no 'Edit squads' control on this screen or anywhere in the app (grep for 'Edit squads' across lib/, test/ and integration_test/ returns only this string), and the scorer arrived here via `pushReplacement` from the squads screen, so the back button does not lead there either. The scorer follows an instruction that cannot be followed; the only real route is out to the Matches tab and 'Resume setup'.

**Why it is real**

The referenced affordance is absent from the widget tree built in this file (Toss winner / Elected to / Opening pair / error / 'Start match') and from the whole codebase, and the screen was reached with pushReplacement (match_squads_screen.dart:100), so the squads screen is not on the stack to pop back to.

---

## 83. [LOW] Tournaments list fetches every tournament that has ever existed, unfiltered and unbounded
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/tournaments/data/tournament_providers.dart`:12

**Failure scenario**

tournamentsListProvider is `from('tournaments').select('id, name, status, city, starts_on, champion_team_id, organizer_id').order('created_at', ascending:false)` with no limit, no city filter and no status filter, and TournamentsListScreen pours the result straight into a ListView.separated (tournaments_list_screen.dart:50-52). The screen has no search box, so a user in Pune scrolls past every tournament ever created anywhere - including years of finished ones, since nothing filters on status or date. Once the platform has tens of thousands of tournaments the Matches tab stalls on open and the user cannot find their own event, which they must instead reach via the 'Join with a code' dialog.

**Why it is real**

Read the provider and the screen; there is no limit anywhere in the chain and no filter parameter on the query. tournaments is indexed only on organizer_id (20260625150100_tournaments.sql:18), so the created_at sort is unindexed too. Cost tracks total platform tournaments, not the user's.

---

## 84. [LOW] Viewer's wagon wheel never updates: _refold() omits inningsWagonProvider, which is never invalidated anywhere in the app
- **file**: `Projects/cricket-app/app/lib/src/features/scoring/presentation/match_viewer_screen.dart`:105

**Failure scenario**

A viewer opens /watch/:id at over 3 and switches to the Charts tab; the wagon wheel shows the 5 shots recorded so far. The scorer keeps scoring and keeps placing shots on the wagon field. Every set_delivery_wagon UPDATE broadcasts and the viewer re-folds, so the Manhattan and worm charts update live - but `_refold()` (lines 101-108) invalidates only matchProvider, matchInningsListProvider and inningsStateProvider per innings. `inningsWagonProvider` (match_providers.dart:155) is a non-autoDispose FutureProvider.family that is never invalidated anywhere in the codebase, so at over 18 the wagon wheel still shows exactly those 5 shots next to a fully up-to-date Manhattan chart. For a viewer who opens the Charts tab before any shot is placed it shows 'No shots recorded yet.' for the entire match.

**Why it is real**

grep across lib/ for `invalidate(inningsWagonProvider` returns zero hits; the provider is watched at match_viewer_screen.dart:913 and is not autoDispose (riverpod 3.3.2 default), so its first resolved value is cached for the process lifetime. The IndexedStack (line 392) keeps all four tabs alive, so even switching tabs does not re-create the watch.

---

## 85. [LOW] retire_batter accepts a last-pair retirement with no incoming batter; all three folds then leave the retired batter at the crease forever
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260706110400_rpc_retire_batter.sql`:27

**Failure scenario**

An 11-man side is 9 down (all_out = 10, so wickets_remaining = 1) and the striker pulls a hamstring. retire_batter's only incoming-batter gate is `if _incoming_batter_id is null and coalesce(wickets_remaining, 99) >= 2 then raise` - at wickets_remaining = 1 a NULL incoming is accepted, and a retired-hurt call writes an event row with wicket_type = 'retired_not_out' and incoming_batter_id = NULL. Every fold's retirement branch then does nothing useful with it: because wicket_type = 'retired_not_out' no wicket is counted (so `_wickets >= _all_out` never fires and the innings does not end), and because incoming_batter_id is NULL the striker/non-striker pair is left untouched (compute_innings_state 20260707190000 lines 57-72; compute_innings_cards 20260707130000 lines 288-301; restamp_innings_strike 20260707140000 lines 42-51). The retired batter stays on strike, and every subsequent ball's runs, balls faced, fours and sixes are credited to a player who has left the field - permanently, since career stats bake from the cards. The mirror-image gap is in the UI: scoring_console_screen.dart line 954 disables the Retire button whenever the incoming dropdown is null, and at 9 down availableIncoming is empty, so the scorer has no way to record the genuine last-pair retirement at all.

**Why it is real**

The guard's own message ("this is not the last wicket") shows it was copied from record_ball, where the last-wicket case is safe because the wicket itself ends the innings. For a retired_not_out no wicket is counted, so the same relaxation produces a state the fold cannot represent: a batter who has retired but is still the striker. Verified in all three live fold definitions - none of them sets _ended or advances the pair on a retirement with a NULL incoming batter, so this is a genuine validation hole rather than a lockstep divergence.

---

## 86. [LOW] searchProvider is keyed per keystroke but is not autoDispose, so a failed search is cached for the session
- **file**: `Projects/cricket-app/app/lib/src/features/discover/data/discover_providers.dart`:124

**Failure scenario**

User opens Messages -> compose (or Discover -> Search) and types "rahul" while connectivity is down for more than the ~30 s riverpod retry budget. `searchProvider('rahul')` ends in a permanent AsyncError. Once back online, retyping the exact same query returns the cached error: `_PeoplePickerSheet` reads `results.value ?? const []` (dm_inbox_screen.dart:201-204) and renders "No players found.", i.e. it asserts the person does not exist; SearchScreen renders "Search failed." with no retry affordance (search_screen.dart:66). The only fix is restarting the app or typing a different string. Every intermediate prefix ("r", "ra", "rah"...) is also retained for the whole session.

**Why it is real**

Riverpod 3 keeps non-autoDispose provider state until the container is disposed (`super.isAutoDispose = false`, riverpod-3.3.2 lib/src/providers/future_provider.dart:189) and its default retry gives up after 10 attempts (~30 s, foundation.dart:54-60). `opponentSearchProvider` in match_providers.dart:23 was given `.autoDispose` for exactly this failure mode, with the reason spelled out in its comment at lines 19-22; the identical shape here was missed.

---

## 87. [LOW] tournamentsListProvider is never refreshed after the organizer changes tournament status, and the list has no pull-to-refresh
- **file**: `Projects/cricket-app/app/lib/src/features/tournaments/presentation/tournaments_list_screen.dart`:20

**Failure scenario**

Organizer opens Matches -> Tournaments (caches `tournamentsListProvider`), taps "Manage", generates fixtures, scores the group games, generates playoffs and finally "Crown the champion". Every one of those actions invalidates only `tournamentOverviewProvider(id)` (manage_tournament_screen.dart:301, 329, 362, 392). Popping back to the list shows the row still chipped with the original status (`_StatusChip`, line 63) and no champion trophy (line 69-74), i.e. "Registration open" for a completed tournament. The screen has no `RefreshIndicator` and no invalidate-on-entry, so the only recovery is an app restart (or waiting for a JWT refresh to bump `currentSessionProvider`, which the provider watches at tournament_providers.dart:10).

**Why it is real**

`tournamentsListProvider` is a plain non-autoDispose FutureProvider (tournament_providers.dart:8) and the create screen invalidates it explicitly (create_tournament_screen.dart:68), proving the cache is known to be sticky; none of the four status-changing organizer actions do the same.

---

