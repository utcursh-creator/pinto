---
type: audit
date: 2026-07-01
project: cricket-app
status: open
note: Master defect map for the one-shot rebuild (144 raw findings -> deduped to distinct issues). Do-it-right pass.
---

I have full confirmation of the codebase structure. Producing the master issue map now.

# Pitch (Cricket App) — MASTER ISSUE MAP & One-Shot Rebuild Plan

> Consolidated from 144 raw audit findings across area + adversarial agents. De-duplicated to **94 distinct issues**. This is the execution plan. Every distinct real issue is preserved; near-identical reports were merged with all their files/root-causes folded in.

---

## 1. Executive Verdict

**Honest state: the app is a beautifully-wired skeleton with no working spine.** The backend is genuinely impressive — a 10-stage delivery-fold engine, full innings/result computation, RLS, realtime broadcast scaffolding, tournament standings/NRR/playoffs, player career stats, DM threads. But almost none of it is reachable, completable, or correct end-to-end from the UI. The recurring pattern is **hollow wiring**: a capable RPC or column exists, the repository method even exists, and the UI simply never calls it (or calls it with hardcoded/placeholder values).

**What actually works:** ball-by-ball scoring of a *single first innings*; team creation; roster display; guest add; basic discover feed read; DM thread send (on the happy path, while both parties sit on the screen); seeded tournament display.

**What is hollow / broken (the themes):**

1. **The match never completes.** No 2nd innings, no innings break, no target, no result is ever written or shown. This is the single highest-leverage failure — it cascades into stats, tournaments, leaderboards, POTM, and history all being permanently empty outside seeded data. (Reported ~8 times.)
2. **There is no working sign-in on a real iOS release build.** Google gate fails (no iOS client id), the email/password shim is `kDebugMode`-only, Apple has no entitlement. The entire identity half is unreachable on device.
3. **"Live" doesn't push.** The viewer channel is created *public* (not `private:true`), so DB-trigger broadcasts are never delivered; and broadcasts only fire on deliveries, not on innings/match status changes; and a cold-start deep-link viewer subscribes with a null token. The app's headline premise is dead end-to-end.
4. **Cricket-rules correctness bugs** in the fold engine: run-out strike attribution ignores the stored `crossed` flag (wrong batter on strike on odd runs); a wicket with no incoming batter leaves the out batter scoring; over/economy math hardcodes `/6`.
5. **Security holes**: every user's phone is readable by any logged-in user; exact author GPS leaks via direct table read; open DMs to anyone; a DM "mark-read" UPDATE policy that lets a participant rewrite the other person's messages; `create_match`/`set_match_result`/`add_tournament_team` accept unvalidated/unauthorized inputs.
6. **Whole features missing**: account management (reset/delete — a store-review blocker), notifications, player/team search & follow, unique handles, multi-use/expiring invites, member removal/leave/delete-team.
7. **Pervasive UX rot**: raw `$e` dumped to users, infinite spinners with no retry, "Team A/Team B" placeholders everywhere instead of real names, no error/empty/retry states, hardcoded "Chat" DM headers.

**Bottom line:** the play→score→result→stats loop must be closed first; until then nothing downstream can hold real data. The rebuild plan below is ordered to make that core loop work earliest, backend-first within each slice.

---

## 2. Complete Issue Register (de-duplicated, grouped by area)

Severity: **B**=blocker, **Ma**=major, **Mi**=minor. Layer: FE / BE / Both.

### 2.1 Auth & Onboarding (`AUTH-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| AUTH-1 | B | Both | **No working sign-in on real iOS release.** Google gate returns false without `GOOGLE_IOS_CLIENT_ID`; email/password shim is `kDebugMode`-gated (vanishes in release); Apple has no entitlement. User is stuck as anon viewer forever. **Root cause/files:** `env.dart:35-41`, `hosted_defines.json`, `ios/Runner/Info.plist` (no reversed-client-id URL scheme), `oauth_sign_in.dart:35-40`, `sign_in_screen.dart:59`. **Fix:** provision iOS OAuth client (id + CFBundleURLTypes per `oauth-provisioning.md`); add Apple capability; never hide the only usable sign-in behind `kDebugMode` on iOS. Verify a real Google sign-in completes on the sim. |
| AUTH-2 | Ma | FE | **Sign-out strands the user with no session.** `anonBootstrapProvider` is a one-shot FutureProvider; after `signOut()` nothing re-creates an anon session, so realtime + anon reads silently break until app relaunch. **Files:** `profile_screen.dart:104-105`, `auth_providers.dart:34-45`. **Fix:** listen to `onAuthStateChange` for `signedOut` and re-`signInAnonymously()` (or convert bootstrap into a listener that re-creates an anon session whenever `currentSession` becomes null). |
| AUTH-3 | Ma | FE | **OAuth over an anon session orphans data.** `signInWithIdToken` mints a *new* user instead of `linkIdentity` over the anonymous session, abandoning anything the anon user created; `create_profile` then inserts a fresh profile under the new uid. **Files:** `oauth_sign_in.dart:66-71`, `auth_providers.dart:37-45`, `create_profile_screen.dart:40-43`. **Fix:** when an anon session exists, upgrade in place via `linkIdentity`/anonymous-conversion so the same uid carries forward; else explicitly migrate/discard and document. |
| AUTH-4 | Ma | FE | **Transient profile-read error traps an onboarded user on Create-profile + data-loss risk.** `auth_gate.dart:17` maps *any* read error → `needsProfile`; `myProfileProvider` has no retry; `create_profile` does a blind INSERT, so an existing user hits PK 23505 dumped raw. **Files:** `auth_gate.dart:17`, `profile_provider.dart:9-18`, `create_profile_screen.dart:40-46`. **Fix:** on profile-read error show a retry/error gate (not `needsProfile`); make create-profile an `upsert(onConflict: id)` and translate 23505 to a friendly message + route into shell. |
| AUTH-5 | Ma | FE | **Create-profile is a name-only stub.** No avatar/city/role/batting; no prefill of the Google/Apple `full_name` already in `userMetadata`; inserts only `{id, display_name}`. New profiles start empty everywhere. **Files:** `create_profile_screen.dart:20-79`, `edit_profile_screen.dart` (already has all controls), `profiles.sql` (has city/batting_style/playing_role/photo_url). **Fix:** prefill name from `session.user.userMetadata['full_name']/['name']`; add the city/role/batting/photo controls from EditProfile so first run produces a complete profile. |
| AUTH-6 | Mi | FE | **Create-profile validation is silent.** Only `trim().isEmpty` guard; whitespace-only no-ops with no message; button always enabled; no maxLength. **Files:** `create_profile_screen.dart:33-34,61-69`. **Fix:** inline validation message, disable Continue until valid, add maxLength. |
| AUTH-7 | Mi | FE | **Sign-out has no confirm/loading/error handling.** Unawaited async, no busy flag, swallowed failures, no confirm dialog, double-tap queues duplicates. **Files:** `profile_screen.dart:103-106`. **Fix:** confirm dialog, awaited busy state, SnackBar on success/failure, explicit route to Discover. |

### 2.2 Identity / Profile (`PROF-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| PROF-1 | Ma | Both | **No unique handle/username anywhere.** Two players can share `display_name`; `/player/:id` exposes a raw UUID; "duplicate handle" cannot even be evaluated. **Files:** `profiles.sql` (no username/handle, no unique constraint), `create_profile_screen.dart`. **Fix:** add unique lowercased `handle` (citext unique); collect+validate at create-profile (live availability check, friendly dup error); use in search and `/player/<handle>`. |
| PROF-2 | Ma | FE | **No account-management surface.** No password reset, no email/phone change, no account deletion; Settings is a permanently disabled dead row. (Store-review + GDPR blocker.) **Files:** `profile_screen.dart:94-99`, `sign_in_screen.dart`. **Fix:** real Settings screen with `resetPasswordForEmail`, `updateUser`, and account-deletion (Edge Function → admin `deleteUser`). |
| PROF-3 | Mi | FE | **Profile error/loading/empty states inadequate.** Raw `$e` dumped, lone spinner, no retry, no pull-to-refresh; same anti-pattern in Discover. **Files:** `profile_screen.dart:21-22`, `discover_screen.dart:94`. **Fix:** reusable error widget + Retry (`ref.invalidate`), `RefreshIndicator`, never interpolate raw `$e`. |
| PROF-4 | Mi | FE | **Edit-profile avatar preview stale + upload error sticky + no save toast.** Initials don't refresh on typed name; failed upload error never clears; Save pops silently. **Files:** `edit_profile_screen.dart:57-58,92,110`. **Fix:** `onChanged: (_) => setState((){})`, clear `_error` at start of each attempt, success SnackBar before pop. |
| PROF-5 | Mi | FE | **Anon Profile/Discover tabs are dead ends.** Anon Profile shows only a sign-in stub; Discover fully replaced by `_SignInToDiscover`. The login-free mode the app is built around is mostly walls. **Files:** `profile_screen.dart:24-39`, `discover_screen.dart:33-34`. **Fix:** give anon states real content (recently watched, browse public tournaments, value-prop). |

### 2.3 Teams & Invites (`TEAM-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| TEAM-1 | B | FE | **No remove-member / leave-team / delete-team UI.** RLS fully supports all three; zero callers in `lib/`. A user is stuck on every team forever; captains can't kick or disband. **Files:** `team_page_screen.dart`, `identity_repository.dart`, `team_members_rls.sql:19-22`, `teams_rls.sql:18-20`. **Fix:** add `removeMember`/`leaveTeam`/`deleteTeam`; per-member overflow + "Leave team" + "Delete team" with confirm; invalidate roster/myTeams after. |
| TEAM-2 | B | Both | **Invite token is single-use *and* unbounded — first tapper wins, then dead.** `accept_invite` flips the whole row to `accepted`; lookup requires `status='pending'`, so the first redeemer consumes it for everyone. **Files:** `rpc_accept_invite.sql:15-36`, `create_team_invite.sql`, `team_page_screen.dart:184`. **Fix:** make multi-use — add `max_uses`/`uses` (or `multi_use`), record redemptions in `team_invite_redemptions` instead of flipping status; keep the partial-unique index to prevent duplicate memberships. (See SEC-7 for the security framing of the same root.) |
| TEAM-3 | Ma/Mi | Both | **No invite expiry / revoke; leaked token grants membership forever.** No `expires_at`, no `max_uses`, no `used_by`; admin expire/cancel policy exists but no UI calls it; TOCTOU window where concurrent callers all read `pending`. **Files:** `team_invites.sql`, `create_team_invite.sql`, `rpc_accept_invite.sql:15-17`. **Fix:** add `expires_at` (default now()+7d); `select … for update` the row in accept_invite, reject if expired/over max_uses, increment uses; add a captain "Active invites" list with revoke; re-mint revokes prior pending tokens. |
| TEAM-4 | Ma | FE | **Invite-by-phone path is dead code.** `team_invites.invited_phone` + a select policy model addressed invites + an invitee inbox, but `create_team_invite` never sets `invited_phone` and no UI surfaces phone invites or an inbox. **Files:** `team_invites.sql:3,22`, `create_team_invite.sql`. **Fix:** either implement the addressed flow (captain "Invite by phone" + "Team invites" inbox querying `invited_phone = my phone` + Accept) **or** drop `invited_phone` and its policy branch. |
| TEAM-5 | Ma | FE | **Captain/keeper/role can't be assigned or shown.** Enum has captain/admin/player and RLS allows admin UPDATE role, but no repo method/UI sets it; roster shows no (C)/(WK) badges. **Files:** `team_page_screen.dart:219-251`, `team_members_rls.sql:14-17`, `enums.sql:3`. **Fix:** add `setMemberRole`; render (C)/(VC)/(A) badges; admin overflow "Make captain/admin/player" with a guard keeping ≥1 captain. |
| TEAM-6 | Mi | Both | **Guest add allows empty/whitespace + duplicate guests.** Whitespace-only is silently rejected (looks broken); RPC inserts any `_guest_name` with no length/uniqueness check; "Guest" fallback renders. **Files:** `team_page_screen.dart:137-165`, `rpc_add_guest_member.sql:14-16`. **Fix:** inline validation in `_addGuest`; server `raise` on empty trimmed name + trim server-side + case-insensitive dup warning. |
| TEAM-7 | Mi | FE | **Team logo can't be set at creation.** Create screen has name+city only; `createTeam` never forwards `_logo_url` even though the RPC accepts it. **Files:** `create_team_screen.dart:60-68`, `identity_repository.dart:53-59`, `rpc_create_team.sql:1`. **Fix:** optional logo picker + forward `_logo_url`. |
| TEAM-8 | Mi | FE | **Team home-ground label never captured.** `_setFromGps` calls `setTeamLocation` with no `_label`; shows "Saved location" forever. **Files:** `team_page_screen.dart:268-296`, `discover_repository.dart:119`, `rpc_set_location.sql:11`. **Fix:** prompt for ground name (or reverse-geocode) and pass `label:`. |
| TEAM-9 | Mi | FE | **Claim inbox shows "A player" / can blank on join failure.** Depends on a fragile embedded FK join; success-toast passes the possibly-"A player" string; no avatar. **Files:** `identity_providers.dart:30-45`, `claim_inbox_screen.dart:74-77`. **Fix:** verify embeds against live data or resolve via `public_profile_minimal`; show avatar+name; explicit "Unknown player" rather than blind approve. |
| TEAM-10 | Mi | Both | **Roster has no sort/order.** Arbitrary DB order; captain not pinned; guests interleaved; no batting-order concept. **Files:** `identity_providers.dart:48-59`, `team_page_screen.dart:94`, `team_members.sql`. **Fix:** at minimum `.order('role').order('created_at')`; ideally add nullable `batting_order` + reorderable admin UI. |
| TEAM-11 | Mi | Both | **No "Request to join" for non-members.** Team page is a read-only dead end for strangers; no join-request backend. **Files:** `team_page_screen.dart:47-48`. **Fix:** self-serve `request_to_join` RPC (pending membership request the admin approves) + "Request to join" button. |
| TEAM-12 | Mi | FE | **My-teams tile crashes on null/deleted team + no refresh.** Force-cast `row['teams'] as Map` throws if embed is null; no `RefreshIndicator`; stale after invite-accept. **Files:** `my_teams_screen.dart:42`, `identity_providers.dart`. **Fix:** null-guard the embed; wrap in `RefreshIndicator` invalidating `myTeamsProvider`. |
| TEAM-13 | Ma | Both | **Teams are near-empty shells: no team match history / W-L / team stats / edit name-city.** Only roster+logo+ground render; `myMatchesProvider` filters by scorer/owner so there's no "our matches" view; no `team_career_stats` RPC. **Files:** `team_page_screen.dart`, `match_providers.dart:185-188`. **Fix:** add edit name/city/logo; "Team matches" tab querying `team_a_id/team_b_id = teamId` with W/L; add `team_career_stats` RPC. |

### 2.4 Match Setup & Scoring Console (`SCOR-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| SCOR-1 | B | FE | **Match never completes — no innings break, no 2nd innings, no result.** `startInnings` is only ever called with `inningsNumber:1` and no target; `setResult` has zero callers; console never reads `s['innings_status']`/`s['result']`. Match stays `live` forever → every downstream feature (stats, tournaments, leaderboards, POTM, champion, history) is permanently empty. (Reported ~8×.) **Files:** `scoring_console_screen.dart:35-42,188-258`, `toss_openers_screen.dart:174-181`, `match_repository.dart:49,205`, `fold_v10_innings_end.sql:117,138`. **Fix:** in `_afterBall`, read `innings_status`; on innings-1 complete → set `matches.status='innings_break'`, open an "Innings break → start chase" flow that calls `startInnings(inningsNumber:2, batting=prev bowling, bowling=prev batting, target=runs1+1)` with fresh openers; on innings-2 complete → read `s['result']` and call `setResult(...)`, flip to `complete`, route to viewer. Add an explicit "End innings / declare" action. |
| SCOR-2 | B | Both | **Wicket with no incoming batter corrupts the innings — out batter keeps scoring.** Console "Record wicket" always pops `true` even when `incoming==null`; fold only swaps when `incoming_batter_id is not null`. (Reported 3×.) **Files:** `scoring_console_screen.dart:394-412`, `fold_v10_innings_end.sql:99-102`, `record_ball_consec_fix.sql:38-45`. **Fix:** disable "Record wicket" until an incoming is chosen (except the genuine last-wicket/all-out case → triggers innings end); in `record_ball` **raise** when a wicket has no `incoming_batter_id` and it isn't the final wicket; mirror in `edit_ball`/`insert_ball`. |
| SCOR-3 | B | BE | **Run-out strike attribution is systematically wrong on odd runs — the stored `crossed` flag is dead data.** Strike rotates from off-bat parity *before* the wicket-replacement block, and `deliveries.crossed` is never read by any fold. Non-striker run out on 1 → engine returns survivor/incoming on the wrong ends. **Files:** `fold_v10_innings_end.sql:71-76,95-102`, `deliveries.sql:18`, `restamp_strike.sql`, `compute_innings_cards.sql`. **Fix:** for a run-out, do NOT rotate from parity — drive end-assignment from `crossed`; replace the dismissed end with the incoming and set strike from `crossed` + end-of-over swap; apply identically to all three folds; wire `_crossed` through `record_ball`. Add pgTAP: striker run out on 1, non-striker run out on 1, run out on 0 with crossed=true. |
| SCOR-4 | Ma | FE | **Run-out/stumping always dismisses the striker; no "who's out?" / "crossed?" / runs-on-ball.** Hard-codes `dismissedId: strikerId`; far-batter run-out is impossible; run-out ball can only be 0 runs. (Reported 3×.) **Files:** `scoring_console_screen.dart:405-411`, `rpc_record_ball.sql`. **Fix:** for run_out/obstructing show a striker/non-striker chooser + "batters crossed?" toggle + runs-completed entry; pass `dismissedPlayerId`+`crossed`. |
| SCOR-5 | Ma | FE | **Incoming-batter dropdown lists already-out / at-crease batters.** Whole batting squad, unfiltered, in both console and ball-log editor. **Files:** `scoring_console_screen.dart:341-344,387-390`, `ball_log_screen.dart:139-142`. **Fix:** exclude current striker, non-striker, and everyone in `fall_of_wickets` before building the dropdown. |
| SCOR-6 | Ma | FE | **Wicket sheet offers only 5 of 11 dismissal types and no fielder.** Missing hit_wicket, retired_out/not_out, obstructing, timed_out, hit_ball_twice; no fielder_id captured → fielding stats permanently empty. **Files:** `scoring_console_screen.dart:333-413`, `match_repository.dart:84`, `scoring_enums.sql:8`, `compute_innings_cards.sql:108-115`. **Fix:** drive chips from the full enum; add a fielder picker (bowling squad) for caught/stumped/run_out and pass `_fielder_id`; add retire path. |
| SCOR-7 | Ma | FE | **Run pad can't enter multi-run extras / wide+runs / no-ball+runs / 5 / 7 / penalty.** Each extra hard-codes `1`; no `5`; no overthrow toggle; penalty unreachable. `record_ball` supports all of it. (Reported 3×, incl. SCOR-7b penalty.) **Files:** `scoring_console_screen.dart:277-285`, `match_repository.dart:72-109`, `rpc_record_ball.sql:3-9`, `fold_v10_innings_end.sql:35,40`. **Fix:** per-extra quantity/combination sheet (Wide→wide runs; No-ball→off-bat runs + byes/leg-byes), add `5`/custom runs + overthrow toggle + "Penalty +5" (add `_extra_penalty` to `recordBall`). |
| SCOR-8 | Ma | FE | **No free-hit enforcement / indicator in the console.** Engine tracks `free_hit_active` and blocks illegal dismissals, but console never reads it; scorer learns via a thrown toast. Banner exists only in the read-only viewer. **Files:** `scoring_console_screen.dart`, `record_ball_consec_fix.sql:38-41`, `match_viewer_screen.dart:424-436`. **Fix:** read `free_hit_active`, show FREE HIT banner, restrict the wicket sheet to run_out/obstructing/hit_ball_twice while active. |
| SCOR-9 | Ma | FE | **Console never reacts to innings end — accepts balls past all-out / last over.** Pad stays enabled; over keeps visually incrementing; fold orphans the extra deliveries silently. **Files:** `scoring_console_screen.dart:188-258,246-247`, `fold_v10_innings_end.sql:33,117,171`. **Fix:** on `innings_status=='completed'`, replace pad with an "Innings complete" panel (result/target summary) + next-innings/end-match action; surface `orphaned_deliveries` as a warning. |
| SCOR-10 | Ma | Both | **Squad selection allows one side empty / no per-team minimum / no squad_size rule.** Gate checks only combined `length < 4`; `create_match` sends no `_rules`, so engine defaults `_squad_size:=11`/`_all_out:=10`; "all out" never triggers at the true count and phantom did-not-bats appear. (Reported 3×.) **Files:** `match_squads_screen.dart:26-29`, `match_repository.dart:12-26`, `rpc_create_match.sql`, `fold_v10_innings_end.sql:24,29`. **Fix:** require ≥2 per side via `_teamOf`; pass real `squad_size` in rules (or derive `all_out` from actual `match_squad` count); validate in `start_innings` that both squads ≥2 and openers are distinct and on the batting side. |
| SCOR-11 | B | Both | **Opponent side can't get a squad — no add-player affordance in match setup; add-guest is admin-gated on the other team.** A scorer who isn't an admin of the opponent team cannot field their side. **Files:** `match_squads_screen.dart`, `team_page_screen.dart:47-48,108-116`, `rpc_add_guest_member.sql`. **Fix:** inline "Add player" per team in the squads screen; new `add_match_guest` RPC authorizing on `is_match_scorer` (not `is_team_admin`), or attach ad-hoc named players to `match_squad` without a `team_members` row. |
| SCOR-12 | Ma | Both | **Squad picker labels + toss chips hardcode "Team A"/"Team B".** Real names available via `matchTeamNamesProvider` but unused; scorer can't tell sides. (Reported 3×, incl. toss screen.) **Files:** `match_squads_screen.dart:67-75`, `toss_openers_screen.dart:64,72`, `match_providers.dart:83`. **Fix:** watch `matchTeamNamesProvider(matchId)` in both screens; fall back to A/B only if a name is genuinely missing. |
| SCOR-13 | Ma | Both | **No captain/keeper/batting-order capture in match setup.** `addSquadMember` never passes `_batting_order/_is_captain/_is_keeper`; `did_not_bat` ordering relies on always-null `batting_order`. **Files:** `match_squads_screen.dart`, `rpc_add_squad_member.sql:1-9`, `match_squad.sql:6-9`, `fold_v10_innings_end.sql:129`. **Fix:** order the XI + tag captain/keeper, pass through `addSquadMember`; render (c)/(wk). |
| SCOR-14 | Mi | FE | **Opening-pair pickers not mutually exclusive; no bowling-side-has-players check.** Striker==non-striker only caught at submit; can start with an empty bowling side. **Files:** `toss_openers_screen.dart:101-104,154-186`. **Fix:** exclude chosen striker from non-striker list; verify both squads non-empty before "Start match". |
| SCOR-15 | Mi/Ma | Both | **Bowler unconstrained: no over/quota cap, no last-bowler exclusion, no figures in picker.** Backend only blocks an immediate repeat (thrown after a ball is scored); no max-overs-per-bowler. **Files:** `scoring_console_screen.dart:308-331`, `record_ball_consec_fix.sql:41-43,51-58`. **Fix:** show each bowler's overs/figures from `compute_innings_state['bowling']`, disable the previous-over bowler, enforce `max_overs_per_bowler` (default `ceil(overs/5)`) client+server. |
| SCOR-16 | Mi | FE | **No manual strike swap / retire-batter control.** `retired_not_out` understood by the fold but no UI triggers it; strike corrections need ball-log surgery. **Files:** `scoring_console_screen.dart:260-306`, `fold_v10_innings_end.sql:36`. **Fix:** add "swap strike" + "Retire batter" (records `retired_not_out` with incoming) + end-of-over summary prompt. |
| SCOR-17 | Mi | FE | **Wagon-wheel sheet has no run context, is tap-dismissible, swallows failures.** Shot drawn the same regardless of runs; accidental dismiss drops the shot; save error is an empty catch. **Files:** `scoring_console_screen.dart:108-120`, `wagon_field.dart`, `match_repository.dart:112`. **Fix:** pass the ball's runs into the sheet/label; `isDismissible:false`; toast on `setDeliveryWagon` failure. |
| SCOR-18 | Mi | FE | **Ball-log editor collapses a delivery to one "type."** Can't represent wide+byes, no-ball+byes, penalty, or fielder; `edit_ball`/`insert_ball` accept all independently. **Files:** `ball_log_screen.dart:244-266,384-395`, `match_repository.dart`. **Fix:** replace the mutually-exclusive ChoiceChip group with independent fields (off-bat runs + each extra + penalty + fielder). |
| SCOR-19 | Mi | FE | **Disabled run pad swallows taps with no feedback; busy-window feels dead.** `AbsorbPointer` + Opacity but no prompt; `_record` early-returns silently during `_busy`. **Files:** `scoring_console_screen.dart:56,246-252`. **Fix:** "Pick a bowler to start the over" snackbar (or auto-open picker); visible busy spinner. |
| SCOR-20 | Mi | FE | **Transfer-scorer list omits guests, includes self, double-pops.** Current user not excluded (hand over to yourself); pops twice assuming console below. **Files:** `match_providers.dart:152-177`, `transfer_scorer_screen.dart:41-42`. **Fix:** exclude current user from candidates; after transfer `context.go` to Matches explicitly. |
| SCOR-21 | Mi | FE | **Chase header ignores fold's required-rate fields.** Shows only "Over X – target N"; `runs_required/balls_remaining/rrr/crr/wickets_remaining` all unread. **Files:** `scoring_console_screen.dart:213-217`, `fold_v10_innings_end.sql:169-170`. **Fix:** render "Need R off B – RRR / CRR" when target set. |
| SCOR-22 | Mi | Both | **No super-over / tie-break flow** despite a `tie_superover` enum value. **Files:** `scoring_console_screen.dart`, `tournament_models.dart:158`. **Fix:** after SCOR-1, on a tie offer "Play super over" (1 over/side), record `tie_superover`. (Defer — needs the core loop first.) |
| SCOR-23 | Mi | BE | **Bowling overs/economy hardcode `/6` and `%6`.** Wrong for `balls_per_over != 6` (the Hundred / custom); only rotation respects `_bpo`. **Files:** `fold_v10_innings_end.sql:154,159-162`. **Fix:** use `_bpo` for every over-notation and economy denominator. |
| SCOR-24 | Mi | BE | **Concurrency: read used to derive strike is unlocked; no optimistic-concurrency token; transfer-scorer doesn't fence in-flight writes.** Two devices can interleave corrections/appends with stale state. **Files:** `record_ball_consec_fix.sql:31`, `rpc_corrections.sql`, `transfer_scorer.sql`. **Fix:** return a delivery-count/version token from `compute_innings_state`; require `record_ball` to pass the expected seq/version and reject on mismatch. |
| SCOR-25 | Mi | BE | **Corrections can silently flip the result with no recompute/warning.** `edit_ball` → `restamp_innings_strike` moves the innings-end boundary, but orphaned deliveries aren't pruned/flagged and `matches.result` is never recomputed (set_match_result is manual/uncalled). **Files:** `restamp_strike.sql`, `rpc_corrections.sql`, `fold_v10_innings_end.sql`. **Fix:** after any correction recompute innings-end/result; if the match was complete re-run `set_match_result` (or null it back); warn in ball-log when an edit changes the orphaned set or result. |

### 2.5 Matches List & Match Lifecycle (`MTCH-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| MTCH-1 | Ma | Both | **Matches list shows "N-over match" with no team names / scores / result / date; no history split.** `myMatchesProvider` selects no team join (unlike `liveMatchesProvider`). (Reported 4×.) **Files:** `matches_screen.dart:59-63`, `match_providers.dart:180-191`. **Fix:** embed `team_a:team_a_id(name),team_b:team_b_id(name)` + result; render "A v B – result" with date; split Live / Upcoming / Completed; completed tap → read-only scorecard. |
| MTCH-2 | Ma/B | Both | **A `setup` (or stranded `live`) match can't be resumed, abandoned, or deleted.** List routes any non-finished match to the console, which dead-ends at "No innings yet. Finish setup first." `setResult('abandoned')` exists but is never called; no delete RPC. (Reported 4×.) **Files:** `matches_screen.dart:73-75`, `scoring_console_screen.dart:175-177`, `rpc_set_result.sql:9-10`. **Fix:** route `setup` → `matchSquads(id)` (resume) — or make the console's empty state offer "Continue setup"; add swipe/long-press "Abandon match" (`setResult('abandoned')`) and a cascade `delete_match` RPC for setup matches with no innings. |
| MTCH-3 | B | Both | **Match result never persisted *or* displayed.** `set_match_result` has zero callers; viewer Info/Live tabs never read `match['result']`/`s['result']` — only raw status text + POTM. Defending-side (`win_by_runs`) win also unhandled. (Reported ~5×, the consume side of SCOR-1.) **Files:** `match_viewer_screen.dart:808-863`, `match_repository.dart:205`, `rpc_set_result.sql`, `fold_v10_innings_end.sql:139-150`. **Fix:** call `set_match_result` from the engine-derived outcome when the chase completes; render a prominent result banner ("X won by N runs/wickets" / "Match tied") on Live + Info, resolving `winner_team_id` via the teams map; handle tie/no-result/abandoned. |
| MTCH-4 | Ma | BE | **Deleting a team referenced by a match orphans it (no cascade, no guard).** `matches.team_a_id/team_b_id/toss_winner_id` and `innings.batting/bowling_team_id` have no ON DELETE action; forcing it blanks team names in the viewer. **Files:** `matches.sql`, `innings.sql`, `teams.sql`. **Fix:** forbid team deletion while referenced (RPC raises listing the matches) **or** soft-delete teams (`deleted_at`) and keep historical references. |
| MTCH-5 | Mi | Both | **Tournament fixtures clutter the organizer's personal Matches tab** as anonymous "N-over match" rows (created with `scorer_id = organizer`, no tournament context). **Files:** `match_providers.dart:180`, `matches_screen.dart`. **Fix:** left-join `tournament_matches` and badge ("CityCup – Group A"), or exclude tournament-linked matches from the personal tab. |
| MTCH-6 | Mi | FE | **Opponent picker lists your own team (and every team).** Self only rejected post-hoc at "Next". **Files:** `start_match_screen.dart:102-117,50-52`. **Fix:** exclude selected `_teamA` from the opponent items. |
| MTCH-7 | Ma | FE | **Discover→match "Propose a match" bridge drops everything but opponent id.** Post's overs/place/`match_at`/id lost; no link back; original poster never notified. **Files:** `post_detail_screen.dart:141-146`, `start_match_screen.dart:33-34`, `routes.dart:30`. **Fix:** pass overs/`match_at`/post-id into the wizard to prefill; on match creation open/append a DM to the post author ("Proposed a match: <link>"). |

### 2.6 Live Viewer & Realtime (`RT-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| RT-1 | B | Both | **Live score never pushes — viewer channel is public, not `private:true`.** DB-trigger broadcasts land in `realtime.messages` gated by RLS that Supabase only evaluates for **private** channels. The DM screen got this right; the viewer didn't. **Files:** `match_viewer_screen.dart:63`, `broadcast.sql:8,30-32`, `dm_thread_screen.dart:58`. **Fix:** `c.channel('match:$id', opts: const RealtimeChannelConfig(private: true))`; verify end-to-end (two clients) that a recorded ball re-folds the watcher. |
| RT-2 | B | BE | **Broadcasts fire only on deliveries — innings-break, 2nd-innings start, and match completion never push.** Only `deliveries_broadcast` exists; no trigger on `innings` or `matches` status/result changes. **Files:** `broadcast.sql:23-25`, `rpc_set_result.sql`, `match_viewer_screen.dart:71-78`. **Fix:** add AFTER UPDATE triggers on `innings` and `matches` calling `realtime.broadcast_changes` on the same `match:<id>` topic (mirror the exception-swallowing pattern); pgTAP for both triggers + an e2e check that completing a match pushes. |
| RT-3 | B | FE | **Cold-start deep-linked `/watch` subscribes before the anon session exists and never re-auths.** `_subscribe` runs in a post-frame callback calling `setAuth(currentSession?.accessToken)` while session is still null; no re-subscribe when the session appears. The headline share use case can't receive live updates. **Files:** `match_viewer_screen.dart:53,62`, `app.dart:18`, `auth_providers.dart`. **Fix:** gate `_subscribe()` on a non-null session; (re)subscribe + `realtime.setAuth(accessToken)` when a session first becomes available and on token refresh; show "connecting" until then. Verify on a true cold-start deep link. |
| RT-4 | Ma | FE | **Viewer crashes on a bad/deleted/forbidden match id.** `matchProvider.maybeSingle()` returns null; `ready = match.hasValue …` is true for a null value, then `match.value!` force-unwraps and throws. **Files:** `match_viewer_screen.dart:161,183`, `match_providers.dart:38`. **Fix:** explicitly handle `match.value == null` → "Match not found"; handle `hasError`; never force-unwrap. |
| RT-5 | Ma | FE | **Viewer spins forever (no error state) when top-level match/innings/squad loads fail.** `ready` only true when all three `hasValue`; on `hasError` it spins permanently. **Files:** `match_viewer_screen.dart:180-181`. **Fix:** render an error state with retry (invalidate providers) when any of the three has error. |
| RT-6 | Mi | FE | **No innings-break presentation; 1st-innings recap buried behind a chip.** Live tab shows the now-complete innings with stale LIVE layout; the innings switcher is gated behind `length > 1`, so during the break there's nothing to review. **Files:** `match_viewer_screen.dart:297-489,552`. **Fix:** explicit innings_break banner ("Innings break – <Team> need <target> to win") driven by `match.status=='innings_break'`; show a recap; make the just-completed innings reviewable even as the only innings. |
| RT-7 | Mi | Both | **Anon viewer sees "Team A/Team B" fallback** when `matchTeamNamesProvider` returns empty (gated RLS / non-live status). **Files:** `match_viewer_screen.dart:100-101,165-167,816-817`, `match_providers.dart`. **Fix:** ensure the anon-readable teams policy covers any `/watch`-reachable status, or expose names via a SECURITY DEFINER match-summary RPC. |

### 2.7 Discover / Looking-For (`DISC-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| DISC-1 | Ma | FE | **Composer drops every cricket-specific field: overs, skill, slots-needed, match date/time, ball-type, contact.** RPC + repo accept all; composer only collects mode/flair/place/details/link/images. Every post is "need players near here." (Reported 3×.) **Files:** `new_post_composer.dart`, `discover_repository.dart:33-69`, `lf_flair_rpc.sql:7-10`, `rpc_posts.sql`. **Fix:** add overs/skill chips/slots stepper/date-time picker (and ball type) and pass through `createPost`. |
| DISC-2 | Ma | Both | **Post card + detail never display overs/skill/slots/match-date — even though providers fetch them.** **Files:** `discover_screen.dart:208-279`, `post_detail_screen.dart:74-148`, `discover_providers.dart:91-105`. **Fix:** render a metadata chip row ("20 ov", skill, "2 players needed", formatted `match_at`) in both. |
| DISC-3 | Ma | FE | **Feed has no overs/skill/date filters despite the RPC supporting `_max_overs/_skill/_on_or_after`.** `DiscoverQuery` only carries lat/lng/radius/mode/flair. (Reported 2×.) **Files:** `discover_models.dart`, `discover_providers.dart:56-73`, `discover_screen.dart:151-206`. **Fix:** extend `DiscoverQuery`, send the args, add skill chips / overs cap / "from date" to `_FilterBar`. |
| DISC-4 | Ma/B | Both | **Location screen shows raw lat/long text fields and never persists a place label.** No map/geocoding; `setMyLocation` called with no `label`, so home base shows "Saved location" forever. (Reported 2×.) **Files:** `location_screen.dart:45-123`, `discover_repository.dart:99-104`. **Fix:** map picker / place search + reverse-geocode → pass `label`; hide raw lat/long behind "advanced". |
| DISC-5 | Ma | Both | **Feed cards + detail omit poster name and team.** `discover_posts` returns `author_id/team_id` but no `display_name`/team name; card shows neither; detail shows "a player". (Reported 2×.) **Files:** `discover_screen.dart:208-279`, `post_detail_screen.dart`, `post_attachments_rpc.sql:31-36` / `rpc_discover_posts.sql`. **Fix:** join `profiles.display_name` + `teams.name` into the RPC row; render "Posted by X (Team Y)" and link the team. |
| DISC-6 | Mi | FE | **Post-type (mode) label rendered twice** on every card and on detail (title + a duplicate chip). **Files:** `discover_screen.dart:215,247-250`, `post_detail_screen.dart:74-84`. **Fix:** render the mode label once. |
| DISC-7 | Mi | Both | **Distance shows "0 m" for nearby posts and is unfriendly.** Server rounds to nearest 100 m → anything under ~50 m becomes 0; no km formatting. **Files:** `discover_screen.dart:237`, `post_attachments_rpc.sql:39`. **Fix:** format "<X m" / "Nearby" / "N.N km" in `LfLabels.distance`; reduce the rounding bucket for short ranges. |
| DISC-8 | Mi | Both | **Invite-accept screen prints raw errors; no invalid/expired/used distinction; no pre-flight token lookup.** **Files:** `invite_accept_screen.dart:38-42`, `rpc_accept_invite.sql:19-21`. **Fix:** pre-resolve the token to show the inviting team name + a clear invalid/expired state; map known error codes to friendly messages. |

### 2.8 Messaging / DMs (`DM-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| DM-1 | Ma | FE | **Thread header hardcoded "Chat" — never shows who you're talking to.** No name/avatar; only `threadId` known. (Reported 2×.) **Files:** `dm_thread_screen.dart:104-105`. **Fix:** resolve the other participant (inbox already does via `dm_participants` join) keyed by threadId; set title + avatar. |
| DM-2 | Ma | FE | **Anon "Message" button silently does nothing.** `getOrCreateDmThread` raises `not authenticated` (28000) when `auth.uid()` is null; no try/catch, no anon gate. **Files:** `post_detail_screen.dart:46-50`, `rpc_dm.sql:5`. **Fix:** gate on `isAnonymousProvider` → route to sign-in; wrap in try/catch + SnackBar. |
| DM-3 | Ma | FE | **DM send loses the message on failure.** Input cleared *before* the awaited insert; bare insert with no try/catch; relies entirely on the broadcast echo, so a dropped echo means the sender never sees their own message. **Files:** `dm_thread_screen.dart:86-92`, `discover_repository.dart:90-96`. **Fix:** don't clear input until insert succeeds; try/catch → restore text + SnackBar; append optimistically (the `_ids` dedupe guards the echo). |
| DM-4 | Ma | Both | **Unread state completely unimplemented** despite `read_at` column + a dedicated RLS update policy. No badge anywhere; opening a thread never marks read. **Files:** `dm_thread_screen.dart`, `discover_providers.dart:136-169`, `dm.sql:21,48-49`. **Fix:** on thread open, `update dm_messages set read_at=now() where sender_id<>me and read_at is null` (via the secured RPC from SEC-4); compute per-thread unread counts in `dmInboxProvider`; badge inbox rows + Discover mail icon. |
| DM-5 | Mi | FE | **DM inbox is static — no live update, no pull-to-refresh.** No realtime subscription, no `RefreshIndicator`, no invalidation. **Files:** `dm_inbox_screen.dart`, `discover_providers.dart`. **Fix:** `RefreshIndicator` invalidating `dmInboxProvider` and/or subscribe to the user's threads to invalidate on new messages. |
| DM-6 | Mi | FE | **No timestamps anywhere** (bubbles or inbox). `created_at` is fetched and discarded. **Files:** `dm_thread_screen.dart`, `dm_inbox_screen.dart:30-43`, `discover_providers.dart`. **Fix:** render relative/day-grouped times on bubbles + trailing last-message time per inbox row. |
| DM-7 | Mi | FE | **DM inbox can't start a new conversation — messaging is reply-only.** No compose/people-picker; thread creation gated behind an open post. **Files:** `dm_inbox_screen.dart`, `discover_repository.dart`. **Fix:** "New message" → people picker (teammates + searched players) → `get_or_create_dm_thread`. (Depends on search, MISS-3.) |

### 2.9 Tournaments (`TOUR-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| TOUR-1 | B | FE | **Tournament fixtures are unscoreable — "Score" jumps straight to the empty console.** Fixtures are inserted in `status='setup'` with no squad/toss/innings; manage screen routes to `scoreMatch`, which dead-ends. So no group match can complete → standings/playoffs/leaderboards/champion never advance. (Reported 2×.) **Files:** `manage_tournament_screen.dart:178-182`, `scoring_console_screen.dart:175`, `rpc_generate_group_fixtures.sql:29-33`. **Fix:** route a `setup` fixture → `matchSquads(matchId)` (then toss → console); better, make the console self-heal by offering "Set up squads & toss" when innings is null. (Same fix unblocks MTCH-2.) |
| TOUR-2 | B | FE | **Organizer can only add their OWN teams.** Add-team list is `myTeamsProvider`; a real multi-team event is impossible. Backend `add_tournament_team` allows any `team_id` for the organizer. (Reported 2×.) **Files:** `manage_tournament_screen.dart:192-199`. **Fix:** team search over `allTeamsProvider` + quick-add placeholder. (See SEC-9 for the consent gate.) |
| TOUR-3 | Ma | FE | **Create screen caps overs at 10/15/20 and discards venue + dates.** RPC + repo accept venue/starts_on/ends_on; screen never collects them. **Files:** `create_tournament_screen.dart:33-81`, `tournament_repository.dart`. **Fix:** free overs input (5–50), venue field, start/end pickers, pass through `createTournament`. |
| TOUR-4 | Ma | Both | **Generated fixtures have no schedule** (no `scheduled_at`/venue) and no UI to set them. **Files:** `rpc_generate_group_fixtures.sql`, `rpc_generate_playoffs.sql`, `manage_tournament_screen.dart`, `tournament_page_screen.dart:208-230`. **Fix:** organizer "edit fixture" action (small `is_tournament_organizer`-gated update RPC) + render date/venue on tiles. |
| TOUR-5 | Ma | BE | **Standings only list teams that have already played a completed match** ("v1" limitation). Table shows "No results yet" / a partial ladder for most of the tournament. **Files:** `rpc_tournament_standings.sql`, `tournament_page_screen.dart:104-138`. **Fix:** seed from `tournament_teams` (all entered teams at zeros) and left-join computed rows. |
| TOUR-6 | Ma | Both | **Public fixture/bracket never shows who won or the scoreline.** `Fixture.statusLine` maps every win to "Result in"/"Completed"; overview returns no innings scores. **Files:** `tournament_models.dart:150-163`, `tournament_page_screen.dart`, `rpc_tournament_overview.sql`. **Fix:** include each completed fixture's two innings scores + winner id in `tournament_overview`; render "A 152/6 beat B 134 by 18 runs". |
| TOUR-7 | Ma | Both | **Leaderboard/POTM/reply/author rows aren't tappable to the player page.** `/player/:id` is a dead-end island; leaderboards key by `member_id` not `profile_id`. **Files:** `tournament_page_screen.dart:336-343`, `post_detail_screen.dart:162-173`, `tournament_models.dart`. **Fix:** return `profile_id` in `tournament_leaderboard`/`match_potm`; make rows tappable to `/player/:profileId` only when claimed. |
| TOUR-8 | Mi | Both | **POTM shows name with no team, no link, never persisted** (recomputed each view → can change on correction). **Files:** `rpc_match_potm.sql`, `tournament_providers.dart`, `tournament_page_screen.dart:336-343`. **Fix:** resolve+show team, make tappable, persist POTM on the match at result time. |
| TOUR-9 | Mi | Both | **Tournament shape hardcoded to 2 groups (A/B) top-2 — `group_count`/`qualifiers_per_group` are a lie.** `generate_playoffs` raises unless 2×2; manage only offers A/B. **Files:** `tournament_repository.dart:24-26`, `manage_tournament_screen.dart:69,217`, `rpc_generate_playoffs.sql`. **Fix:** either remove the knobs to match the baked 2×2 reality, or generalize playoffs + group picker to honor the config. |

### 2.10 Stats & Player Pages (`STAT-*`)

| ID | Sev | Layer | Title |
|----|-----|-------|-------|
| STAT-1 | Ma | Both | **Player stats screen reachable only from your own profile + team rosters** (consume side of TOUR-7). **Files:** `tournament_page_screen.dart`, `post_detail_screen.dart`, `tournament_models.dart`. **Fix:** as TOUR-7 — make leaderboard/POTM/reply/author rows link to `/player/:profileId`. |
| STAT-2 | Mi | Both | **Unclaimed guests have no career page destination.** Keyed by `team_members.id`; appear in leaderboards but tapping leads nowhere. **Files:** `player_views.sql`, `player_public_profile.sql`, `stats_providers.dart`. **Fix:** member-keyed read-only stats page for guests (`player_career_stats` already accepts any player_key), or make guest names non-tappable with a "claim this player" prompt. |
| STAT-3 | Mi | FE | **Recent-form chip renders "0*" for a match the player never batted.** `runs=0/out=false` → "0*". **Files:** `stats_models.dart:174`, `player_recent_form.sql`. **Fix:** treat `balls==0 && !out` as "DNB" (or a dash). |

### 2.11 Security findings — see §4 (`SEC-*`).
### 2.12 Whole missing features — see §5 (`MISS-*`).

---

## 3. Cricket-Rules Correctness (read this carefully — these make scorecards *wrong*)

These are the issues that produce an **incorrect scorecard**, not just a UX gap. Highest priority for a cricketer.

| ID | Sev | What's wrong on the card |
|----|-----|--------------------------|
| **SCOR-3** | B | **Run-out strike attribution wrong on odd runs.** The `crossed` flag captured on every delivery is *never read by any fold*; strike is rotated from off-bat parity before the wicket-replacement block. Result: after a run-out completing an odd number of runs, the wrong batter is on strike and the incoming batter enters at the wrong end. Fix in all three folds (`compute_innings_state`, `restamp_innings_strike`, `compute_innings_cards`) + wire `_crossed` through `record_ball`. Add pgTAP for striker/non-striker run out on 1 and run out on 0 with crossed=true. |
| **SCOR-2** | B | **Wicket with no incoming batter → dismissed batter keeps scoring.** Subsequent runs/balls are credited to an out player; striker label never changes. Backend must `raise` unless it's the last wicket; UI must disable "Record wicket" until an incoming is chosen. |
| **SCOR-4** | Ma | **Run-out/stumping always dismisses the striker.** Non-striker run-out is impossible; run-out ball forced to 0 runs. Need who's-out + crossed? + runs entry. |
| **SCOR-6** | Ma | **Only 5 of 11 dismissal types; no fielder credited.** hit_wicket/retired/obstructing/timed_out/hit_ball_twice unreachable; catches/stumpings/run-outs credit no fielder → career fielding always zero. |
| **SCOR-7** | Ma | **Multi-run extras impossible.** 4 byes, wide+2, no-ball+4 off the bat, overthrows (5/7), 5-run penalty all unrepresentable from the console. |
| **SCOR-8** | Ma | **Free-hit not enforced.** A bowled/lbw/caught on a free hit is accepted by the console (only the read-only viewer shows the banner). |
| **SCOR-10 / SCOR-13** | Ma | **`all out` / `did not bat` are meaningless** because `squad_size` defaults to 11 regardless of real squad, and `batting_order` is never set → arbitrary DNB ordering and innings that never end on all-out. |
| **SCOR-15** | Mi/Ma | **No max-overs-per-bowler cap** (a single bowler can bowl every over in a T20). |
| **SCOR-23** | Mi | **Over notation + economy hardcode `/6`** → wrong for non-6-ball formats the app explicitly supports. |
| **SCOR-1 / MTCH-3** | B | **No result is ever computed against the laws** because the match can't reach a 2nd innings; tie/win-by-runs/win-by-wickets/DLS enums are all dead. |
| **SCOR-22** | Mi | **No super-over** for a tied limited-overs match. |

---

## 4. Security Findings (treat as release-gating)

| ID | Sev | Layer | Finding & Fix |
|----|-----|-------|----------------|
| **SEC-1** | B | BE | **Every user's phone number is readable by any logged-in user (PII leak).** `profiles.phone` + blanket `profiles_select_authenticated … using(true)`; Postgres RLS is row-level, no column GRANT, so `GET /profiles?select=phone` dumps all numbers. **Files:** `profiles.sql:2`, `profiles_rls.sql:3,6-9`, `public_profile_minimal.sql:2-3`. **Fix:** split a public view (id, display_name, photo_url, city, styles, role) granted to authenticated/anon and make `profiles` self-read-only (`using (id = auth.uid())`), routing roster/search reads through the view + `public_profile_minimal`; **or** drop `phone` from `profiles` entirely. The app already only reads its own profile, so self-read won't break screens. |
| **SEC-2** | Ma | BE | **Exact author GPS leaks via direct read of `looking_for_posts`.** Table stores the precise `geog` and is granted `select … using(true)`, defeating `discover_posts`'s 100 m rounding (trilateration). **Files:** `looking_for_posts.sql:8,22-23`, `rpc_discover_posts.sql:12`. **Fix:** REVOKE table select; force all feed reads through `discover_posts()`/a post-detail RPC returning only rounded distance + label; if a direct read is needed, expose a view omitting `geog`. |
| **SEC-3** | Ma | BE | **Open DMs — any authenticated user can DM any other by UUID.** `get_or_create_dm_thread` only checks `_other <> me`; no relationship/consent, no block/report, no rate limit. Profile UUIDs are visible across the app → real harassment vector. **Files:** `rpc_dm.sql:1-14`, `dm.sql`, `discover_repository.dart`. **Fix:** gate thread creation on an existing relationship (replied to their post / shared team) or add a `blocked_users` table consulted in the WITH CHECK + report flow + rate limit; reject DMs against anonymous-only profiles. |
| **SEC-4** | Ma | BE | **DM "mark-read" UPDATE policy lets a participant rewrite/forge ANY message in the thread** (including the other person's body, sender_id, created_at). `dm_messages_update_read` uses table UPDATE scoped only to thread participation; no column scoping, no trigger pinning. **Files:** `dm.sql:38,48-49`. **Fix:** REVOKE table UPDATE from authenticated; replace with a SECURITY DEFINER `mark_thread_read(_thread_id)` that only sets `read_at` where `sender_id <> auth.uid()` — or a BEFORE UPDATE trigger that raises unless the only changed column is `read_at` and `OLD.sender_id <> auth.uid()`. |
| **SEC-5** | Ma | BE | **`create_match` has no team-membership check — anyone can fabricate matches between teams they don't belong to** and score fake results into those teams'/players' public career stats. **Files:** `rpc_create_match.sql:7-13`. **Fix:** require `is_team_admin(_team_a) or is_team_admin(_team_b)`; consider requiring the opponent to accept before the match counts toward stats. |
| **SEC-6** | Ma | BE | **`set_match_result` accepts an arbitrary `winner_team_id`** (any UUID, even a non-participant), stored verbatim and consumed by POTM tiebreak + standings. **Files:** `rpc_set_result.sql:6-11`, `rpc_match_potm.sql:26`. **Fix:** validate `_winner_team_id in (team_a_id, team_b_id)` for wins; require null for tie/no_result/abandoned; reject results on non-live/ineligible matches. |
| **SEC-7** | Mi/B | BE | **Team invite token reusable + never expires** (TOCTOU window; one leaked link = unlimited joiners). **Files:** `team_invites.sql:1-9`, `rpc_accept_invite.sql:15-36`, `create_team_invite.sql:12`. **Fix:** add `expires_at` + `uses`/`max_uses`; `select … for update`, reject expired/over-limit, increment, mark accepted only for single-use; re-mint revokes prior pending tokens. (Same root as TEAM-2/TEAM-3.) |
| **SEC-8** | Ma | BE | **`add_tournament_team` enrolls ANY team without that team's consent** (and then auto-generates real matches for them). **Files:** `rpc_add_tournament_team.sql:5-13`, `rpc_generate_group_fixtures.sql:29-33`. **Fix:** require `is_team_admin(_team_id)` by the organizer, or a `tournament_invites` accept flow before enrolment/fixture generation. |
| **SEC-9** | Mi | BE | **Anon realtime receive policy not status-gated.** `match_broadcast_receive` authorizes on `topic() like 'match:%'` with no check that the match status is public — broader than the documented privacy model (would leak any future setup-time broadcasts). **Files:** `broadcast.sql:30-32`, `anon_read_viewer.sql:7-9`. **Fix:** parse the match id from the topic and require an EXISTS on `matches` with public status, mirroring the table policies. |
| **SEC-10** | Mi | BE | **Broadcast triggers swallow all exceptions** (`when others then return null`) with no logging — masks programming errors / corruption. **Files:** `broadcast.sql:18-19`, `dm_broadcast.sql:7`. **Fix:** `raise warning 'broadcast failed: %', sqlerrm; return null;` and/or catch only the specific realtime exception classes. |

---

## 5. Whole Missing Features (completeness critic)

| ID | Feature | Scope | Notes |
|----|---------|-------|-------|
| **MISS-1** | **Match completion: 2nd innings + result-setting** (SCOR-1, MTCH-3, RT-2) | **v1 — must** | The single biggest gap. Nothing downstream holds real data without it. |
| **MISS-2** | **Notifications subsystem** (reply / claim / invite-accept / DM / match-live) | **v1 — must (in-app inbox + badge minimum)** | Zero notifications today; the geo-matchmaking loop dies silently. Table + AFTER INSERT triggers + unread-count provider + screen + tab badge. APNs/FCM (task #61) can follow, but the in-app inbox is v1. |
| **MISS-3** | **Player & team search + follow** | **v1 — search must; follow defer** | No way to find a player/team by name or follow anyone; the people-graph doesn't exist. Ship name-search RPC (trigram/ILIKE, SECURITY DEFINER returning `public_profile_minimal`) + search screen in v1; follows table + "following" feed can defer. Unblocks DM-7. |
| **MISS-4** | **Account management & store-compliance Settings** (PROF-2) | **v1 — must (store blocker)** | Password reset, email/phone change, account deletion, privacy policy + terms links, help/about/version. Apple/Google reject without account-deletion + privacy link. |
| **MISS-5** | **Unique handles** (PROF-1) | **v1 — must** | Required for addressable players, search results, and `/player/<handle>` links. |
| **MISS-6** | **Multi-use / expiring / revocable team invites + manage screen** (TEAM-2/3, SEC-7) | **v1 — must** | Current single-use-then-dead behavior makes the shareable-link feature unusable. |
| **MISS-7** | **Member removal / leave / delete-team** (TEAM-1) | **v1 — must** | Backend supports it; no UI. |
| **MISS-8** | **Deep links / App & Universal Links** (`/watch /player /invite /tournament`) | **v1 — must (the share story)** | No URL scheme / App Links registered, so every advertised share link opens a browser to a non-existent site; the Apple-on-Android OAuth redirect scheme is likewise unregistered. **Files:** `AndroidManifest.xml:25-28`, `Info.plist`, `app_router.dart:48-56`, `identity_repository.dart:107`, `oauth_sign_in.dart:82`. **Fix:** register App Links intent-filter (autoVerify, real host) + custom-scheme VIEW filter on Android; CFBundleURLTypes + Associated Domains on iOS; host `assetlinks.json` / AASA. |
| **MISS-9** | **Scorecard export / full-card share** | **defer** | Only a single summary image today; no full batting+bowling card PDF/image share. Add a "Share scorecard" rendering `compute_innings_cards` to a tall image/PDF. |
| **MISS-10** | **Super-over / tie-break** (SCOR-22) | **defer** | Needs the core 2nd-innings loop first. |
| **MISS-11** | **Team stats / team match history** (TEAM-13) | **v1 — history must; team-stats RPC can follow** | A team with no record has no reason to exist; ship a "Team matches" tab in v1. |
| **MISS-12** | **Generalized tournament shape (>2 groups, top-1)** (TOUR-9) | **defer** | Either remove the knobs or generalize playoffs. For v1, make the baked 2×2 honest. |

---

## 6. Slice-by-Slice Rebuild Plan

Backend-first within each slice. Ordered so the **core play→score→result→view** loop works as early as possible, then the social/discovery layer, then polish. Each slice lists its issue IDs, migrations, frontend work, and the from-scratch playthrough that gates it as done.

---

### Slice 0 — Foundations: Auth that works on device + session lifecycle
**Why first:** nothing is testable on a real build without a working sign-in and a stable session.
**Issues:** AUTH-1, AUTH-2, AUTH-3, AUTH-4, AUTH-5, AUTH-6, AUTH-7, PROF-1 (handle), MISS-5, MISS-8 (deep links), SEC-1 (phone PII — do it now since it's a base-policy change).
**Backend / migrations:**
- `profiles`: add `handle citext unique` (PROF-1); split a **public profile view** (id, display_name, photo_url, city, styles, role) granted to authenticated/anon; make base `profiles` self-read-only (SEC-1). Route roster/search reads through the view + `public_profile_minimal`.
- Provision iOS OAuth client config (not a migration but a build artifact): `GOOGLE_IOS_CLIENT_ID`, `Info.plist` URL scheme, Apple entitlement.
**Frontend:**
- Real sign-in on release (Google + Apple + email/password not `kDebugMode`-gated). `linkIdentity` over anon session. Auth-state listener re-creates anon session on `signedOut`. Auth gate: read-error → retry state, not `needsProfile`. Create-profile: upsert, name prefill from `userMetadata`, handle field with live availability check, city/role/batting/photo, validation. Sign-out confirm + busy + SnackBar. Register App/Universal Links + custom scheme.
**Done when (cold, real iOS build):** install fresh → app boots anon → open `/watch/<live>` deep link from a chat app and it lands *in the app* → tap Continue with Google → account created, anon data carried forward → handle availability validates → complete profile with name prefilled + city/role → sign out → app drops to anon and still reads Discover/realtime → sign back in. A second logged-in user *cannot* read your phone via the API.

---

### Slice 1 — Core scoring loop: setup that produces a real innings, correctly
**Why:** the engine is the heart; make a single innings fully correct and start-able for any match (incl. opponent squads).
**Issues:** SCOR-2, SCOR-3, SCOR-4, SCOR-5, SCOR-6, SCOR-7, SCOR-8, SCOR-10, SCOR-11, SCOR-12, SCOR-13, SCOR-14, SCOR-15, SCOR-16, SCOR-19, SCOR-23, SEC-5.
**Backend / migrations:**
- `record_ball`: raise on wicket-without-incoming (except last) (SCOR-2); wire `_crossed` and drive run-out end-assignment from `crossed` in **all three folds** (SCOR-3); enforce `max_overs_per_bowler` (SCOR-15); validate `_winner`/dismissal inputs.
- `compute_innings_state` / `compute_innings_cards`: use `_bpo` for all over/economy math (SCOR-23); derive `all_out` from real `match_squad` count or passed `squad_size` (SCOR-10).
- `create_match`: require `is_team_admin` of a participating team (SEC-5); accept `_rules`/`squad_size`.
- New `add_match_guest(match_id, team_id, name)` authorized on `is_match_scorer` (SCOR-11).
- `start_innings`: validate both squads ≥2, distinct openers on batting side (SCOR-10/14).
- **pgTAP:** run-out strike cases (SCOR-3), wicket-without-incoming raise (SCOR-2), all-out at true count (SCOR-10), economy/over for `bpo≠6` (SCOR-23).
**Frontend:**
- Squads screen: real team names, per-team ≥2 gate, inline "Add player" for either side, captain/keeper/batting-order capture. Toss screen: real names, mutually-exclusive openers, bowling-side check. Console: full extras quantity/combination sheet + 5/7/penalty/overthrow; wicket sheet with all 11 types + fielder picker + filtered incoming list + who's-out/crossed for run-out; free-hit banner + restricted dismissals; manual swap-strike/retire; bowler picker with figures + quota + last-bowler disabled; busy/no-bowler feedback.
**Done when:** create a match (as a team admin) vs an opponent team you don't own → add guests to *both* sides → set captain/keeper/order → toss → score a full first innings including a wide+2, a no-ball+4, 4 byes, a caught (with fielder), a non-striker run-out on 1 (survivor keeps strike — verify the card), a retired-not-out → all-out triggers at the real squad size → the scorecard is *correct* (strike, fielding credit, extras, DNB order). pgTAP green.

---

### Slice 2 — Close the loop: innings break, 2nd innings, result, history
**Why:** this is the keystone that makes every downstream feature hold real data.
**Issues:** SCOR-1, SCOR-9, SCOR-21, SCOR-25, MTCH-1, MTCH-2, MTCH-3, MTCH-4, SEC-6, MISS-1.
**Backend / migrations:**
- `set_match_result`: validate winner ∈ {team_a, team_b}; null for tie/no-result/abandoned; reject on ineligible status (SEC-6).
- Status transitions: a way to mark `innings_break` (status update or small RPC); recompute result after corrections / re-run `set_match_result` (SCOR-25).
- `delete_match` (cascade innings/deliveries) for setup/owner; `set_match_result('abandoned')` path (MTCH-2).
- Team-delete guard or soft-delete to avoid orphaned matches (MTCH-4).
- `my_matches` select: embed team names + result (MTCH-1).
**Frontend:**
- Console `_afterBall`: on `innings_status=='completed'` → set `innings_break`, "start chase" flow (swap teams, target=runs1+1, fresh openers) for innings 1; for innings 2 read `s['result']` → `setResult` → route to viewer. "Innings complete" panel replaces pad; chase header shows "Need R off B – RRR/CRR". Explicit "End innings/declare". Matches list: "A v B – result", date, Live/Upcoming/Completed split, completed → read-only scorecard; resume `setup` → squads; abandon/delete actions.
**Done when:** from Slice-1's first innings → "Innings break" appears with target → pick chasing openers → score the chase → on the winning run a **result banner** appears ("X won by N wickets"), status flips to `complete`, `matches.result` is persisted → the match shows in the Completed section with team names + result → opening it shows the full read-only scorecard. A `setup` match can be resumed or abandoned.

---

### Slice 3 — Live that actually pushes
**Why:** the headline "live" premise; depends on a completable match to be worth watching.
**Issues:** RT-1, RT-2, RT-3, RT-4, RT-5, RT-6, RT-7, SEC-9, SEC-10.
**Backend / migrations:**
- AFTER UPDATE triggers on `innings` and `matches` broadcasting on `match:<id>` (RT-2), mirroring the swallow pattern but with `raise warning` logging (SEC-10).
- Status-gate the `match_broadcast_receive` policy (SEC-9). Ensure anon-readable teams policy covers all `/watch` statuses (RT-7).
- **pgTAP:** both new triggers exist; receive policy rejects non-public matches.
**Frontend:**
- Viewer channel `private: true` (RT-1); gate `_subscribe` on a non-null session + re-auth on session/token change (RT-3); "Match not found" + error/retry states, no force-unwrap (RT-4/5); innings-break banner + 1st-innings recap reviewable as the only innings (RT-6).
**Done when (two devices):** device A scores; device B opens the shared `/watch` link **cold (logged out)** → score updates live ball-by-ball → at innings break B sees the break banner + target update live → at match end B sees the result banner appear *without re-opening* → opening a garbage/deleted id shows "Match not found", not a crash.

---

### Slice 4 — Tournaments end-to-end
**Why:** now that matches complete + push, tournaments can advance with real data.
**Issues:** TOUR-1, TOUR-2, TOUR-3, TOUR-4, TOUR-5, TOUR-6, TOUR-7, TOUR-8, TOUR-9, MTCH-5, STAT-1, STAT-2, STAT-3, SEC-8.
**Backend / migrations:**
- `add_tournament_team`: require `is_team_admin` or a `tournament_invites` accept flow (SEC-8).
- `tournament_standings`: seed from `tournament_teams` (all teams at zeros) + left-join (TOUR-5).
- `tournament_overview`: include each completed fixture's two innings scores + winner id (TOUR-6).
- `tournament_leaderboard`/`match_potm`: return `profile_id`; persist POTM at result time (TOUR-7/8).
- `create_tournament`/fixtures: accept/store venue + dates + `scheduled_at` per fixture; an `is_tournament_organizer`-gated fixture-edit RPC (TOUR-3/4). Generalize or honestly fix the 2×2 shape (TOUR-9).
**Frontend:**
- Manage: team search over all teams (TOUR-2); route `setup` fixtures → squads (TOUR-1); fixture date/venue editor (TOUR-4); create screen free overs + venue + dates (TOUR-3). Public page: full standings ladder, fixture/bracket scorelines + winner (TOUR-6), tappable leaderboard/POTM/author rows → `/player/:profileId` (TOUR-7, STAT-1); DNB→"DNB" fix (STAT-3); badge tournament fixtures out of the personal Matches tab (MTCH-5).
**Done when:** organizer creates a 6-team, 40-over tournament with venue+dates → searches and adds teams they don't own (with consent) → generates group fixtures → every team shows in the table at P0 from the start → scores a group fixture via squads→toss→console→result → standings + NRR update, the fixture tile shows "A 152/6 beat B 134 by 18 runs" → generate playoffs → leaderboard rows tap through to player career pages.

---

### Slice 5 — Discover & matchmaking that carries real intent
**Why:** the geo loop only works if posts carry overs/skill/slots/date and are filterable + safe.
**Issues:** DISC-1, DISC-2, DISC-3, DISC-4, DISC-5, DISC-6, DISC-7, DISC-8, MTCH-6, MTCH-7, SEC-2, MISS-3 (search).
**Backend / migrations:**
- REVOKE direct select on `looking_for_posts`; force reads through `discover_posts`/post-detail RPC (SEC-2).
- `discover_posts`: join author `display_name` + team name (DISC-5); reduce short-range rounding (DISC-7).
- Name-search RPC over profiles/teams (trigram/ILIKE, SECURITY DEFINER → `public_profile_minimal`) (MISS-3).
**Frontend:**
- Composer: overs/skill/slots/date-time/ball-type → `createPost` (DISC-1). Card+detail: render those + poster/team (DISC-2/5), single mode label (DISC-6), friendly distance (DISC-7). Filter bar: skill/overs/date (DISC-3). Location: map/place-search + reverse-geocode label (DISC-4). Invite-accept: pre-flight token lookup + friendly states (DISC-8). Propose-match bridge carries overs/date/post-id + DMs the author (MTCH-7). Opponent picker excludes self (MTCH-6). Search screen reachable from Discover (MISS-3).
**Done when:** post a "team seeking opponent, 20-over, intermediate, next Sunday, 3 slots" → it shows all fields + your name/team on the card → another user filters Discover to "intermediate / ≤20 overs / this weekend" and finds it → taps "Propose a match" → the wizard pre-fills overs/date, creates the match, and DMs the poster → searching a player by name opens their career page. The raw `geog` is no longer readable directly.

---

### Slice 6 — Messaging, notifications, and the social spine
**Why:** ties the loop together so users learn that someone replied/joined/messaged.
**Issues:** DM-1, DM-2, DM-3, DM-4, DM-5, DM-6, DM-7, SEC-3, SEC-4, MISS-2 (notifications).
**Backend / migrations:**
- `blocked_users` + relationship/consent gate + rate limit in `get_or_create_dm_thread`; reject anon-only targets (SEC-3).
- REVOKE table UPDATE on `dm_messages`; `mark_thread_read(_thread_id)` SECURITY DEFINER setting only `read_at` (SEC-4, enables DM-4).
- `notifications` table (recipient_id, type, ref_id, body, read_at) + AFTER INSERT triggers on `post_replies`, `guest_claim_requests`, invite-accept, `dm_messages`, match→live (MISS-2).
**Frontend:**
- Thread header = other participant name+avatar (DM-1); anon Message → sign-in gate (DM-2); send: don't clear until success, optimistic append, error restore (DM-3); mark-read on open + unread badges on inbox/Discover mail icon (DM-4); inbox live + pull-to-refresh (DM-5); timestamps (DM-6); compose/new-chat via people picker (DM-7). Notifications screen + tab badge + unread-count provider (MISS-2).
**Done when:** user A replies to user B's post → B gets an in-app notification + badge → B opens the DM (header shows A's name) → A and B exchange messages (timestamps, unread clears, optimistic send survives a flaky network) → A cannot edit B's message body via the API, cannot DM a stranger with no relationship, and can block A. New conversations can be started from the inbox.

---

### Slice 7 — Teams, account management, store-readiness, polish
**Why:** the remaining management surfaces, store-blockers, and UX rot.
**Issues:** TEAM-1, TEAM-3 (UI), TEAM-4, TEAM-5, TEAM-6, TEAM-7, TEAM-8, TEAM-9, TEAM-10, TEAM-11, TEAM-12, TEAM-13, MISS-4, MISS-6 (manage-invites UI), MISS-7, MISS-11, PROF-2, PROF-3, PROF-4, PROF-5, SCOR-17, SCOR-18, SCOR-20, SCOR-22 (defer), SCOR-24, MISS-9 (defer).
**Backend / migrations:**
- `team_career_stats` RPC (TEAM-13); `delete_team`/role-update wiring if missing; account-deletion Edge Function (MISS-4); concurrency token from `compute_innings_state` (SCOR-24).
**Frontend:**
- Team page: remove member / leave / delete / edit name-city-logo (TEAM-1/7/13, MISS-7); role badges + change (TEAM-5); guest validation (TEAM-6); ground label (TEAM-8); roster sort (TEAM-10); request-to-join (TEAM-11); my-teams null-guard + refresh (TEAM-12); active-invites manage screen with revoke (TEAM-3/MISS-6); claim-inbox names/avatars (TEAM-9). Settings screen: reset password, change email/phone, **delete account**, privacy + terms links, help/about/version (PROF-2/MISS-4). Reusable error/retry/refresh everywhere (PROF-3); edit-profile polish (PROF-4); anon Profile/Discover real content (PROF-5). Ball-log full composition editor (SCOR-18); wagon polish (SCOR-17); transfer-scorer self-exclusion (SCOR-20).
**Done when:** a captain edits the team name, promotes a co-admin, removes a mis-added guest, revokes a leaked invite, and deletes a defunct team → a user leaves a team and requests to join another → from Settings a user resets their password and **deletes their account** (data scrubbed) → privacy/terms links resolve → every load error shows a friendly message + Retry, no raw `$e`, no infinite spinner. (Defer: super-over, full-card export, generalized tournament shapes.)

---

### Cross-cutting acceptance gate (the "do-it-right" cold test)
A single uninstalled→installed playthrough that must pass before calling the rebuild done:
1. Fresh install → anon → open a shared `/watch` link cold → live score updates → result banner appears live.
2. Sign in with Google on a real iOS build → complete a handle-bearing profile → create a team → invite 3 players via one multi-use link → all 3 join.
3. Create a match vs an opponent team, field both sides, score both innings (with a correctly-attributed non-striker run-out, a caught-with-fielder, multi-run extras) → result persisted → appears in history with a correct scorecard.
4. Run a 6-team tournament to a champion with live standings/NRR and tappable player pages.
5. Post a looking-for ad with full intent → another user filters, finds, proposes a match, and DMs you → you get a notification.
6. From Settings, delete your account.

No step may dump a raw exception, spin forever, show "Team A/Team B", or leak another user's phone/GPS.