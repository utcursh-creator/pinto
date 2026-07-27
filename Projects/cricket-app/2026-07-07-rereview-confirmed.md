# Fix-run re-review - CONFIRMED findings

Six dimensions x adversarial skeptic verification, 37 agents, 3.57M tokens.
**19 confirmed, 12 refuted.** Run id `wf_528f0fb6-945`.

Each finding below survived a skeptic whose instruction was to REFUTE it and
to default to refuted when unconvinced. Work straight down this list.

## 1. [CRITICAL] Rule-1 survivor: authGateProvider (sync) watches myProfileProvider (async), so every Supabase token refresh wipes the navigation stack back to /discover
- **dimension**: providers
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/core/auth/auth_gate.dart`:13

**Failure scenario**

A signed-in scorer is deep in the app - say /matches/<id>/score, half way through the first innings, or /matches/tournaments/<tid>/manage. About an hour in (or the first time they background the app and come back with a stale JWT), supabase_flutter auto-refreshes the token and emits AuthChangeEvent.tokenRefreshed. authStateChangesProvider emits -> currentSessionProvider (a sync Provider that watches that StreamProvider) recomputes and returns a NEW Session; gotrue's Session.== compares accessToken and refreshToken, both of which just changed, so the value is NOT equal and dependents are notified. myProfileProvider watches currentSessionProvider, so it rebuilds -> AsyncLoading with isReloading == true. authGateProvider does profile.when(loading: () => AuthGate.loading, ...) and Riverpod 3.3.2's when() defaults skipLoadingOnReload to FALSE (verified in ~/.pub-cache/hosted/pub.dev/riverpod-3.3.2/lib/src/core/async_value.dart:243), so the loading branch IS taken and the gate flips ready -> loading. RouterRefresh (ref.listen(authGateProvider)) calls notifyListeners, GoRouter re-runs redirect, and onboardingRedirect's loading branch (app_router.dart:82) returns `loc == Routes.splash ? null : Routes.splash`. The whole stack is replaced by /splash; ~200ms later my_profile() returns, the gate goes ready, and the ready branch sends them to Routes.discover. The scorer is now on the Discover tab with the console gone, mid-innings, having touched nothing.

**Why it is real**

This is exactly the shape the fix run declared eradicated (commit dba1ab9, 'sync provider watching async provider (3 instances)'), still present in the two most central providers: authGateProvider watches the FutureProvider myProfileProvider, and currentSessionProvider watches the StreamProvider authStateChangesProvider. Every link is verified in source, not inferred: Session.== compares accessToken/refreshToken (gotrue-2.22.0/lib/src/types/session.dart:119-131); skipLoadingOnReload defaults to false; the loading branch of onboardingRedirect unconditionally returns Routes.splash for any location that is not splash; RouterRefresh fires on any authGateProvider change. Nothing anywhere passes skipLoadingOnReload: true. This is invisible to the test suite because the journey tests and widget tests finish long before a JWT expires - exactly the class of bug the run's own notes say only the device catches.

**Skeptic could not refute it**

NOT REFUTED - every link verified in source, plus a runtime probe.

1. auth_gate.dart:10-21 says exactly what the finder claims: `final authGateProvider = Provider<AuthGate>((ref) { final session = ref.watch(currentSessionProvider); if (isAnonymousSession(session)) return AuthGate.anonymous; final profile = ref.watch(myProfileProvider); return profile.when(data:..., loading: () => AuthGate.loading, error: ...); })` - a sync Provider consuming a FutureProvider with no skip flags. `grep -rn "skipLoadingOnReload" lib/` returns nothing.

2. profile_provider.dart:10 watches the WHOLE session object (`ref.watch(currentSessionProvider)`), not `.select((s) => s?.user.id)`, so any new Session invalidates it. auth_providers.dart:12-15: `currentSessionProvider` is `Provider<Session?>` that watches the `onAuthStateChange` StreamProvider and returns `client.auth.currentSession`.

3. The token-refresh trigger is real. gotrue 2.22.0 `_executeRefresh` (gotrue_client.dart ~1476-1478) does `_saveSession(session); notifyAllSubscribers(AuthChangeEvent.tokenRefreshed);` - the NEW session is installed before the event, so `currentSession` returns a different object. `Session.operator ==` (session.dart ~113-130) compares accessToken/refreshToken/user -> unequal after a refresh -> riverpod's defaultUpdateShouldNotify fires. `AuthState` (auth_state.dart:4-18) has no `==` at all, so AsyncData<AuthState> is always unequal and currentSessionProvider always recomputes. Auto-refresh is a `Timer.periodic(Constants.autoRefreshTickDuration = 10s)` firing `_callRefreshToken` when `expiresInTicks <= 3`; supabase_flutter 2.15 `supabase_auth.dart:157-166` starts it on AppLifecycleState.resumed and stops on paused - so a foregrounded app refreshes ~30s before a 1h JWT expires, and ticks immediately on resum

---

## 2. [HIGH] Leaving a team you have played for is irreversible — every re-entry path is blocked by the new left_at tombstone
- **dimension**: sql
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707180000_leave_team.sql`:100

**Failure scenario**

Priya is a player on "Rovers CC" and has appeared in one match. She taps Leave team. `leave_team` takes the `_has_history` branch and keeps her `team_members` row with `left_at = now()`. A week later the captain re-invites her. (1) Invite link: `accept_invite` (20260703170000_team_invites_multiuse.sql:47) does `insert ... on conflict (team_id, profile_id) where profile_id is not null do nothing` — the tombstone row collides, `_membership_id` comes back NULL, so the ELSE branch selects her DEPARTED row id and returns it without burning a use. `invite_accept_screen.dart` gets a non-null id and reports success. But `is_team_member`/`is_team_admin` now require `left_at is null`, and `myTeamsProvider` filters `.isFilter('left_at', null)`, so the team never appears and she has no rights on it. (2) Request to join: `request_to_join` (20260703190100_team_join_requests.sql:27-29) checks `exists (select 1 from team_members where team_id = _team_id and profile_id = _me)` with no `left_at is null`, so it raises 'you are already on this team'. (3) Guest claim: `approve_guest_claim` Guard 2 (20260615141401_rpc_guest_claims.sql:66-70) raises 'claimer already a member of this team' for the same reason. All three doors are shut, and the partial unique index `team_members_unique_profile on (team_id, profile_id) where profile_id is not null` (20260615140501_team_members.sql:15) has no `left_at is null` predicate, so no fresh row can ever be inserted either.

**Why it is real**

The migration converts departure from a DELETE into a retained row but only teaches `is_team_member` and `is_team_admin` about `left_at`. Every membership-existence check outside those two helpers still sees the tombstone as a live membership. I read all three call sites and the index predicate; none filter `left_at`. Test 115-leave-team.test.sql covers departure and authz revocation but has no rejoin case, so nothing catches it. The invite path is the worst variant because it reports success — the user is told they joined a team they are not on.

**Skeptic could not refute it**

Could not refute — every link in the chain is exactly as described in the code.

CONFIRMED:
1. /Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707180000_leave_team.sql:100 stamps left_at=now() when _has_history. `grep -rn "left_at" backend/supabase/migrations/` returns hits ONLY in this file — no later migration teaches any other function about the column. Only is_team_member (L27-34) and is_team_admin (L36-45) are updated.
2. accept_invite live definition is 20260703170000_team_invites_multiuse.sql:45-61 (nothing redefines it after 07-03). `on conflict (team_id, profile_id) where profile_id is not null do nothing returning id` yields NULL against the tombstone; the `if _membership_id is null` branch then selects the DEPARTED row id with no left_at filter and returns it non-null, without burning a use. invite_accept_screen.dart:34-39 shows 'You joined the team' and navigates to Routes.myTeams, where myTeamsProvider (identity_providers.dart:12-18) applies .isFilter('left_at', null) — so the team is absent. False success confirmed.
3. request_to_join (20260703190100_team_join_requests.sql:27-30): `exists (... where team_id = _team_id and profile_id = _me)` with no left_at clause -> raises 'you are already on this team'.
4. approve_guest_claim Guard 2 (20260615141401_rpc_guest_claims.sql:66-71): same shape -> 'claimer already a member of this team'.
5. Unique index team_members_unique_profile (20260615140501_team_members.sql:15-17) is partial on `profile_id is not null` only; no migration alters it. No fresh row can be inserted.
6. Reachability confirmed: team_page_screen.dart:52 offers 'Leave team' to ANY member (only edit/delete are admin-gated); _teamAction case 'leave' (L306-311) -> identity_reposit

---

## 3. [HIGH] accept_invite silently no-ops for a departed member: the app says "You joined the team" and they are still gone
- **dimension**: left_at
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260703170000_team_invites_multiuse.sql`:47

**Failure scenario**

Priya plays two matches for Ravens XI, then taps Leave team. leave_team finds history, so her row survives with left_at stamped. A month later the captain shares a fresh invite link. Priya opens /invite/<token>, team_invite_preview returns redeemable=true, she taps "Join Ravens XI". accept_invite's `insert ... on conflict (team_id, profile_id) ... do nothing` hits her existing row and does nothing; _membership_id comes back null so the fallback `select id from team_members where team_id = _team_id and profile_id = auth.uid()` returns her DEPARTED row id; the RPC returns it with no error and does not even burn an invite use. invite_accept_screen.dart:37-39 then shows the SnackBar "You joined the team" and context.go(Routes.myTeams). My Teams (identity_providers.dart:17, filters left_at) does not list Ravens XI. The roster (identity_providers.dart:65) does not show her. is_team_member/is_team_admin (20260707180000_leave_team.sql:32,43) return false. She has no membership, no error, and no other door: request_to_join rejects her too. She can tap Join forever and nothing will ever change.

**Why it is real**

I read accept_invite in 20260707150000_tournament_invites_multiuse.sql's predecessor 20260703170000_team_invites_multiuse.sql lines 45-58 and the app handler in app/lib/src/features/teams/presentation/invite_accept_screen.dart lines 28-53. The conflict target is the partial unique index team_members_unique_profile (20260615140501_team_members.sql), which is on (team_id, profile_id) only - left_at is not part of it, so a tombstone row absorbs the insert. Nothing in the whole repo clears left_at: `grep -rn left_at backend/supabase app/lib` returns 12 hits and every one either sets it (leave_team) or filters on it. Before this fix run the row would have been deleted and the insert would have succeeded, so this is a regression introduced by the soft-departure change.

**Skeptic could not refute it**

Confirmed on all points; I could not refute it.

CODE CHAIN, VERIFIED BY READING:
1. backend/supabase/migrations/20260615140501_team_members.sql:16-18 - `create unique index team_members_unique_profile on public.team_members (team_id, profile_id) where profile_id is not null`. left_at is NOT in the index, so a departed row still occupies the (team, profile) slot.
2. backend/supabase/migrations/20260707180000_leave_team.sql:98-103 - a member with history gets `update team_members set left_at = now()`; only a member with NO history is deleted. The tombstone state is real and reachable.
3. backend/supabase/migrations/20260703170000_team_invites_multiuse.sql:45-58 - `insert ... on conflict (team_id, profile_id) where profile_id is not null do nothing returning id into _membership_id`, then `if _membership_id is null then select id into _membership_id from public.team_members where team_id = _team_id and profile_id = auth.uid();`. The fallback select has NO left_at filter. PL/pgSQL INSERT ... RETURNING INTO without STRICT assigns NULL when zero rows return, so the DO NOTHING path reaches the fallback, returns the TOMBSTONE row id, raises nothing, and skips the `uses = uses + 1` branch. left_at is never cleared.
4. Same file lines 68-79 - team_invite_preview only checks status/expires_at/uses, so redeemable=true for a departed member; the Join button is offered.
5. app/lib/src/features/teams/presentation/invite_accept_screen.dart:33-39 - acceptInvite returns a non-null String, no throw, so the SnackBar "You joined the team" fires and context.go(Routes.myTeams) runs. identity_repository.dart:141-144 only casts the id.
6. app/lib/src/features/identity/data/identity_providers.dart:17 (My Teams) and :65 (roster) both `.isFilter('left_at', null)` - she appears in neither. is_team_

---

## 4. [HIGH] request_to_join tells a departed player "you are already on this team" on the same screen that offers them a Request-to-join button
- **dimension**: left_at
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260703190100_team_join_requests.sql`:28

**Failure scenario**

Same departed player, second door. team_page_screen.dart:119 renders the "Request to join" button when `uid != null && !isAnon && myRow == null`, and myRow is derived from teamRosterProvider, which filters left_at - so a departed member sees the button. Tapping it calls request_to_join, whose first guard is `if exists (select 1 from team_members where team_id = _team_id and profile_id = _me)` with NO left_at filter. It matches her tombstone and raises P0001 'you are already on this team'. team_page_screen.dart:210 maps that to the SnackBar "You are already on this team." - shown on a page that is simultaneously showing her a Request-to-join button and a Members list she is not in. There is no third door: the admin has no UI to re-add a registered player (a direct insert into team_members would raise 23505 on the same partial unique index). The same blind spot is in respond_join_request (line 77): a request that was pending when she left is approved with `on conflict ... do nothing`, so the admin sees the request flip to 'approved' while she is still departed.

**Why it is real**

Read request_to_join lines 26-30 and respond_join_request lines 73-79 in 20260703190100_team_join_requests.sql, plus app/lib/src/features/teams/presentation/team_page_screen.dart lines 27-35 (myRow from teamRosterProvider), 118-125 (the button gate) and 199-215 (the error mapping). teamRosterProvider filters left_at (identity_providers.dart:65) but the RPC does not, so the two disagree by construction on exactly the tombstone rows. Combined with the accept_invite finding, a soft-departed member has no path back onto the team through any surface in the app.

**Skeptic could not refute it**

Could not refute - the claim is confirmed by direct reading of the code.

Verified chain:
1. /Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/identity/data/identity_repository.dart:77-78 - removeMember() calls the leave_team RPC.
2. backend/supabase/migrations/20260707180000_leave_team.sql:99-103 - leave_team sets left_at = now() (tombstone) whenever the member has history in match_squad / innings openers / any of six delivery columns; it only hard-deletes when there is no history. tests/115-leave-team.test.sql asserts this, so the tombstone is intended.
3. app/lib/src/features/identity/data/identity_providers.dart:65 - teamRosterProvider applies .isFilter('left_at', null), so the tombstone row is absent from the roster.
4. app/lib/src/features/teams/presentation/team_page_screen.dart:68-71 derives myRow from that filtered roster, so myRow == null for a departed member; line 118 (uid != null && !isAnon && myRow == null) renders the "Request to join" button for her.
5. backend/supabase/migrations/20260703190100_team_join_requests.sql:27-30 - the first guard is `if exists (select 1 from public.team_members where team_id = _team_id and profile_id = _me)` with NO left_at filter. The function is SECURITY DEFINER so RLS does not hide the tombstone; it matches and raises P0001 'you are already on this team'.
6. team_page_screen.dart:211-213 maps that string to the SnackBar 'You are already on this team.' - shown on a page that is simultaneously offering the Request-to-join button and a Members list she is not in.

Refutation attempts that all failed:
- No later migration redefines request_to_join: `grep -rn "request_to_join" backend/supabase/migrations/` returns only 20260703190100. `left_at` appears in exactly one migr

---

## 5. [HIGH] A departed guest's name is permanently burned: add_guest_member/add_match_guest reject re-adding someone who is not on the roster
- **dimension**: left_at
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260703180000_guest_name_validation.sql`:21

**Failure scenario**

Captain adds guest "Rahul" to Ravens XI, picks him for a match, a ball is bowled to him. Rahul stops turning up, so the captain opens the member's overflow menu and taps Remove (team_page_screen.dart:388, repo.removeMember -> leave_team). leave_team sees deliveries history and stamps left_at; the row keeps guest_name = 'Rahul'. The roster now shows no Rahul. Three months later Rahul is back and the captain taps "Add guest player" and types Rahul. add_guest_member's duplicate guard is `exists (select 1 from team_members where team_id = _team_id and lower(guest_name) = lower(_name))` with no left_at filter, so it matches the tombstone and raises 'a guest with this name is already on the team'. humanError passes our own P0001 copy straight through, so the captain reads a sentence that flatly contradicts the roster in front of him, with no way to resolve it - the name is unusable on that team forever. add_match_guest (20260703180100_match_guest_validation.sql:22-26) has the identical guard, so the same wall appears mid-match-setup when the scorer tries to add Rahul to the squad. Note this only bites guests who have PLAYED: a guest with no history is hard-deleted by leave_team, so the name is freed - i.e. it fails precisely for the players who matter.

**Why it is real**

Read the duplicate guard in 20260703180000_guest_name_validation.sql lines 20-25 and the identical one in 20260703180100_match_guest_validation.sql lines 21-26; both scan team_members unfiltered. Read leave_team (20260707180000_leave_team.sql lines 88-101): the update-vs-delete branch keys on history, and the update leaves guest_name untouched. Confirmed the removal path is UI-reachable: team_page_screen.dart:144 sets `adminMenu: isAdmin && member['profile_id'] != uid`, which is true for every guest row (profile_id is null), and _memberAction case 'remove' calls repo.removeMember -> leave_team. Confirmed humanError surfaces P0001 copy verbatim (app/lib/src/core/ui/human_error.dart lines 19-21).

**Skeptic could not refute it**

Could not refute — every link verified in source. (1) The duplicate guard in 20260703180000_guest_name_validation.sql:20-25 and 20260703180100_match_guest_validation.sql:21-26 scans team_members with no left_at filter, and these are the live definitions (no later CREATE OR REPLACE; `grep -rn left_at backend/supabase/migrations/` matches ONLY 20260707180000_leave_team.sql, so no other schema object is left_at-aware). (2) leave_team lines 88-101 take the UPDATE branch when the member has match_squad/innings/deliveries history and leave guest_name intact; the team_members_immutable_identity trigger (20260707120000) blocks only team_id/profile_id changes, so the left_at stamp succeeds. (3) There is no un-leave path anywhere — nothing sets left_at back to null, and leave_team early-returns on an already-departed row. (4) Reachability confirmed: team_page_screen.dart:144 sets adminMenu = isAdmin && member['profile_id'] != uid, true for every guest row (profile_id null), and _MemberTile line 571 adds the 'Remove from team' PopupMenuItem unconditionally (only the role items are gated on !isGuest); _memberAction 'remove' calls repo.removeMember -> leave_team (identity_repository.dart:77-78). (5) The departed guest becomes invisible: teamRosterProvider (identity_providers.dart:65) and the squad picker teamMembersProvider (match_providers.dart:41) both apply .isFilter('left_at', null). (6) Re-add paths team_page_screen.dart:455 (add_guest_member) and match_squads_screen.dart:222 (add_match_guest) both surface the P0001 copy verbatim via humanError (human_error.dart:18-19; the message passes _looksHumanWritten and is <140 chars). No unique index, no app-side pre-check, and no test documents this as intended (115-leave-team.test.sql never re-adds a departed name). The only mitigatio

---

## 6. [HIGH] Finishing a tournament fixture never invalidates tournamentOverviewProvider, so the organizer can never generate the playoffs
- **dimension**: providers
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart`:661

**Failure scenario**

Organizer is on /matches/tournaments/<tid>/manage (ManageTournamentScreen watches tournamentOverviewProvider(tid)). They tap a group fixture -> context.push(Routes.matchSquads) -> squads -> pushReplacement toss -> pushReplacement console -> score the match -> 'Finish match & view scorecard'. _finishMatch invalidates only matchProvider(matchId) and myMatchesProvider, then pushReplacement to /watch/<id>. They pop back to the manage screen, which is still mounted in the stack and still holding the pre-match TournamentOverview. tournamentOverviewProvider is a keepAlive FutureProvider.family (Riverpod 3.3.2 defaults isAutoDispose = false, verified in lib/src/providers/future_provider.dart:107 and the family ctor at :189), the manage screen has no RefreshIndicator, and grep shows tournamentOverviewProvider is invalidated ONLY inside manage_tournament_screen.dart (lines 301/329/362/392) - never from the scoring path. So the fixture still reads 'Upcoming'/'Live', and _groupStage's allDone = group.every((f) => f.isComplete) stays false: 'Generate playoffs' is permanently disabled under the text 'Finish every group match to seed the semifinals.' Leaving and re-entering via the Tournaments list does not help - the same cached family instance is returned. Only killing and relaunching the app unsticks the tournament. Worse, tapping the stale fixture again routes on f.isUpcoming to Routes.matchSquads, dropping the organizer back into the setup wizard for a match that is already live/complete.

**Why it is real**

Fixture.status comes exclusively from the tournament_overview payload (tournament_models.dart:140, isComplete at :166); there is no per-match fallback and no realtime channel on the tournaments feature. myMatchesProvider deliberately filters tournament matches out (MTCH-5), so the Matches tab is not an alternate surface either - the manage screen and the public page are the only two views of a fixture, and both are driven by the one frozen provider. This is the same write-then-navigate class the run fixed for matchSquadProvider and matchProvider, just missed one level up.

**Skeptic could not refute it**

Could not refute — the claim holds on every checkable point.

VERIFIED:
1. tournament_providers.dart:21 declares `FutureProvider.family` with no autoDispose. riverpod 3.3.2 source confirms the default: future_provider.dart:107 (`super.isAutoDispose = false`) and FutureProviderFamily ctor :189 (same). So the cached TournamentOverview survives for the whole process, listeners or not. It watches only supabaseClientProvider, a plain `Provider` returning `Supabase.instance.client` that never changes — and notably NOT currentSessionProvider (unlike tournamentsListProvider, which does).
2. Repo-wide grep for tournamentOverviewProvider = 8 hits: declaration, 2 watches (manage_tournament_screen.dart:25, tournament_page_screen.dart:28), 4 invalidations all inside manage_tournament_screen.dart (301/329/362/392), 1 test override. scoring_console_screen.dart:659-660 `_finishMatch` invalidates only matchProvider + myMatchesProvider.
3. No alternate refresh: manage screen has no RefreshIndicator (the 8 screens that do, do not include either tournament screen), no realtime channel, no RouteObserver/AppLifecycleListener anywhere in app/lib. main.dart mounts one ProviderScope; app.dart never rebuilds it. myMatchesProvider filters tournament fixtures out (match_providers.dart:222-227, MTCH-5), and the public page reads the same family instance, so manage + public page are the only two views and both are frozen.
4. Navigation is as described: manage (`/matches/tournaments/:tid/manage`) and `:matchId/squads` are both in the matches StatefulShellBranch (app_router.dart:237-306); squads->toss->console are pushReplacements of the same imperative match; `/watch/:matchId` is top-level (:130). The manage page and its live ref.watch stay in the branch stack throughout, and popping /watch lands bac

---

## 7. [HIGH] "Sign out" on the create-profile screen leaves the user on the create-profile screen - the new escape hatch does not escape
- **dimension**: navigation
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/onboarding/presentation/create_profile_screen.dart`:139

**Failure scenario**

A signed-in user with no profiles row is pinned to /onboarding/create-profile by the needsProfile branch (the redirect replaced the stack, so ModalRoute.canPop is false, there is no back button, and this screen passes no onEnterApp so it gets no home affordance either). Their save keeps failing (handle collision they cannot get past, backend down, wrong Google account), so they tap the new "Sign out" action. _signOut calls auth.signOut() and invalidates myProfileProvider; the session becomes null, so isAnonymousSession() returns true and authGateProvider yields AuthGate.anonymous. RouterRefresh notifies, the redirect runs with loc == '/onboarding/create-profile', and the anonymous branch is `return loc == Routes.splash ? Routes.discover : null;` - createProfile is not splash, so it returns null and nothing navigates. The user is still staring at the Create profile form, now signed out, with no back button, no home button and no tab bar. Worse, the form is still live: anonBootstrapProvider re-creates an anonymous session on the signedOut event, _canSave is still true (name filled, _handleFree still true), so tapping Continue upserts a profiles row keyed to the freshly minted ANONYMOUS user id, and the gate stays anonymous so the screen still does not move.

**Why it is real**

The code comment on _signOut asserts "Signing out drops the gate back to anonymous, so the router lands them on Discover", but onboardingRedirect's anonymous case (app_router.dart:84) only redirects away from Routes.splash and returns null for every other location, including createProfile. Both files are new in this diff and there is no widget test covering the sign-out path. Fix: either have the anonymous branch also push createProfile/signIn to Discover, or make _signOut navigate explicitly (context.go(Routes.discover)) after the sign-out completes.

**Skeptic could not refute it**

CONFIRMED - I could not refute it; I reproduced it.

1. The code says what the finder claims. app_router.dart:83-84 is `case AuthGate.anonymous: return loc == Routes.splash ? Routes.discover : null;` and Routes.createProfile is '/onboarding/create-profile', so it returns null. create_profile_screen.dart:139-146 `_signOut()` calls auth.signOut(), invalidates myProfileProvider, and performs no navigation; its doc comment ("the router lands them on Discover") is factually wrong.

2. Empirically reproduced. I wrote a throwaway widget test (since deleted) driving the real PitchApp/GoRouter with authGateProvider overridden by a mutable Notifier: landed on CreateProfileScreen via needsProfile, then flipped the gate to anonymous (exactly the state signOut() produces) and pumpAndSettle'd. Output: pure onboardingRedirect(anonymous, createProfile) = null; still-on-create-profile = 1; discover = 0; BackButton count = 0 both before and after. The user does not move.

3. Refutation attempts that failed:
- No loading/error bounce off splash. auth_gate.dart:12 short-circuits `if (isAnonymousSession(session)) return AuthGate.anonymous;` BEFORE watching myProfileProvider, so with session==null the gate goes straight to anonymous - there is no loading window that would push them to /splash (which is the only location the anonymous branch redirects). anonBootstrapProvider (auth_providers.dart:52-57) then re-mints an anon session, which is still anonymous, so the gate value doesn't even change and no re-redirect occurs.
- No back affordance. AdaptiveScaffold._leading only renders the home button when onEnterApp != null, and CreateProfileScreen passes none. No auto-implied back button either: go_router's redirect rebuilds the match list from the redirected location, discarding the pushed /si

---

## 8. [HIGH] A player who has left the team stays in a resumed squad, invisible and unremovable, and is re-written to the server on "Next: toss"
- **dimension**: matchsetup
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/presentation/match_squads_screen.dart`:36

**Failure scenario**

Match M is in 'setup'. The scorer saves squads for Alpha with two members: Leaver (batting 1, captain) and Stayer (batting 2). Before the toss, Leaver leaves Alpha (or an admin removes them). Because Leaver already has a match_squad row, leave_team sets left_at instead of deleting (20260707180000_leave_team.sql). The scorer reopens the squads screen to resume setup. I confirmed the resulting render with a widget probe (ProviderScope overriding matchSquadProvider with Leaver+Stayer and teamMembersProvider('A') with Stayer only): (1) no checkbox is rendered for Leaver, so the scorer can neither see nor deselect them; (2) the CTA reads "Next: toss (4 picked)" - Leaver is still counted; (3) the surviving Alpha player is labelled "2.  Stayer" with no "1." anywhere on that side; (4) the Captain DropdownButton has value=mLeaver and renders its label as "-", and its menu offers "-" as a selectable captain (nameOf() searches `rows`, which the new filter excludes); (5) _next()'s per-team minimum counts 2 for Alpha although only 1 selectable player is on the roster, so the gate passes; (6) _next() then calls addSquadMember for mLeaver, and add_squad_member (20260707130200) validates only `tm.id = _team_member_id and tm.team_id = _team_id`, never `left_at is null`, so the departed player is rewritten into the squad. The toss screen's opener dropdowns read matchSquadProvider (which embeds team_members with no left_at filter), so Leaver is offered as an opening batter and the match starts with them at the crease.

**Why it is real**

The fix run added `.isFilter('left_at', null)` to teamMembersProvider (match_providers.dart:41) but _prefillFrom (match_squads_screen.dart:36) still seeds _selected/_teamOf/_captainOf from matchSquadProvider, which has no such filter. The two sources are now out of sync and nothing reconciles them: _selected can contain ids that have no row in `rows`, and every downstream computation (teamOrder numbering at line 279, nameOf at line 247, the roleRow items at line 262, the a<2/b<2 gate at line 60) is driven off _selected. I verified all five symptoms by rendering the screen; there is no exception, it just silently renders wrong. The server has no backstop either - add_squad_member's participant check does not look at left_at.

**Skeptic could not refute it**

CONFIRMED, not refuted. I opened every file and reproduced the behaviour with a widget probe.

Code facts:
- match_providers.dart:41 — teamMembersProvider gained `.isFilter('left_at', null)` in this fix run (git diff 65e2029..HEAD confirms it is new surface). matchSquadProvider (lines 55-68) reads match_squad and embeds team_members with no left_at predicate.
- match_squads_screen.dart:36 — _prefillFrom seeds _selected/_teamOf/_captainOf from matchSquadProvider; _TeamPicker renders checkboxes from teamMembersProvider. Nothing reconciles the two sets.
- 20260707180000_leave_team.sql — _has_history includes `select 1 from public.match_squad where team_member_id = _membership_id`, so anyone already in a saved squad ALWAYS takes the `update ... set left_at = now()` branch. The delete branch is unreachable for them, so this is the only possible outcome, not a corner case.
- 20260707130200_add_squad_member_validation.sql — both the RPC (`where tm.id = _team_member_id and tm.team_id = _team_id`) and the match_squad_write_scorer RLS policy omit `left_at is null`. grep for left_at across backend/supabase/migrations returns hits ONLY in the leave_team migration; no trigger cleans up match_squad.
- start_innings (20260706111400) only requires the opener to have a match_squad row, so a departed player passes. team_members_select_authenticated is `using (true)`, so the embed resolves and the toss screen renders the name rather than crashing.
- Reachability: matches_screen.dart:149/177 ("Resume setup" / tap on a non-started match) routes to Routes.matchSquads(id); team_page_screen.dart:311 and :416 ("Leave team" / "Remove this player") call identity_repository.dart:78 -> leave_team RPC.

Empirical probe (temporary widget test, since deleted). Overrode matchSquadProvider with Leaver(o

---

## 9. [HIGH] JOURNEY D: the Undo/Swap/Retire assertions cannot detect the AbsorbPointer regression they name
- **dimension**: tests
- **file**: `Projects/cricket-app/app/integration_test/user_journeys_test.dart`:439

**Failure scenario**

Revert the fix: move `_betweenBallRow` back inside `_pad`, i.e. back under the `AbsorbPointer(absorbing: _bowlerId == null || _busy)` at scoring_console_screen.dart:514. Journey D still passes. `expect(find.widgetWithText(OutlinedButton, 'Undo'), findsOneWidget)` proves the widget is in the tree, and finders traverse straight through AbsorbPointer, so all three presence assertions (lines 439-442) hold. The follow-up taps at 444 and 450 then hit an absorbed hit-test region; `tester.tap` only emits a `warnIfMissed` warning, it does not fail, so nothing happens, no 'Could not swap'/'Could not undo' text appears, and the two `findsNothing` assertions pass too.

**Why it is real**

The comment at 437-438 states the defect precisely: the buttons 'used to sit inside the AbsorbPointer and were dead whenever no bowler was selected'. The test asserts presence, not reachability, and it never reaches the failing state at all - a bowler is selected at 389-395 and the 1-over match never ends an over, so `_bowlerId` is non-null for the whole journey and `absorbing` would be false even in the reverted build. Nothing here exercises the no-bowler case.

**Skeptic could not refute it**

NOT REFUTED — every premise verified against the code and the installed Flutter SDK.

1. Scope: the assertions are new surface. `git diff 65e2029..HEAD -- app/integration_test/user_journeys_test.dart` adds them (hunk lines 267-280). `scoring_console_screen.dart` is NOT in the diff, so these assertions are the only thing this run added to guard the AbsorbPointer fix.

2. The no-bowler state is unreachable in Journey D. In /Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/presentation/scoring_console_screen.dart, `_bowlerId` is nulled in only 3 places: field init (L25), `_afterBall` when `legal % bpo == 0` (L42-48), and `_startSecondInnings` (L693). `bpo` defaults to 6 (L375). Journey D records one no-ball-with-byes (0 legal) plus '1' and '4' (2 legal); 2 % 6 != 0 and the innings never ends. So `absorbing: _bowlerId == null || _busy` (L515) is false throughout — in the reverted build too. Stronger: the journey CANNOT reach the assertions with no bowler, because `Extras` lives inside `_pad`; if `_bowlerId` were null the tap at test L414 would open the bowler sheet and `settle(find.text('This ball was'))` at L415 would call `fail(...)`.

3. Finders traverse AbsorbPointer. `_Btn` (L1324) builds `OutlinedButton(child: Text(label))`, so `find.widgetWithText(OutlinedButton,'Undo')` matches on the element tree irrespective of hit-testing. `_pad` (L796) is a `SingleChildScrollView` + `Column(mainAxisSize: min)`, so all children are built eagerly — even a `_betweenBallRow` moved back inside `_pad` and scrolled offscreen still satisfies findsOneWidget.

4. `tester.tap` on an absorbed/missed target warns, does not fail. Verified in /Users/utkarsh/development/flutter/packages/flutter_test/lib/src/controller.dart: `tap` 

---

## 10. [HIGH] JOURNEY B: the 'back to feed' wait is a no-op and no assertion checks the post was created
- **dimension**: tests
- **file**: `Projects/cricket-app/app/integration_test/user_journeys_test.dart`:260

**Failure scenario**

Make `create_looking_for_post` fail (revoke it, break the params, drop the composer's write). The composer catches it, renders `humanError(e)` = 'Something went wrong. Try again.', and stays on screen. `await settle(tester, find.text('Discover'), label: 'back_to_feed')` returns on its first pump anyway, because the composer is a child route of `/discover` inside `StatefulShellRoute.indexedStack` (app_router.dart:195-198) and `AdaptiveTabShell` renders a nav item with `label: 'Discover'` (adaptive_tab_shell.dart:32/55) on every shell screen. The two remaining assertions (264-265) are `findsNothing` on strings the composer's `humanError` path cannot produce. Journey B passes with zero posts created.

**Why it is real**

The journey's stated purpose is 'post a looking-for ad -> find it -> propose'. Neither 'find it' nor 'propose' is performed, and there is no assertion anywhere that the post exists - not `find.text('Need an opponent $run')` in the feed, not a count, nothing. Every assertion in the test is negative.

**Skeptic could not refute it**

CONFIRMED — I tried to break each link and every one held.

1. The composer really is a child route inside the shell branch. `app/lib/src/core/routing/app_router.dart` puts `GoRoute(path: 'compose', builder: (_, _) => const NewPostComposer())` in the `routes:` list of the `/discover` GoRoute, inside `StatefulShellBranch(navigatorKey: discoverKey)` of `StatefulShellRoute.indexedStack`. There is no `parentNavigatorKey` anywhere in the file (grep returned nothing), so the composer is pushed onto the branch navigator *inside* `AdaptiveTabShell`'s `Scaffold.body`. The `bottomNavigationBar` is never covered.

2. `adaptive_tab_shell.dart` renders `label: 'Discover'` on both platforms — a `NavigationDestination` on Material and a `BottomNavigationBarItem` on Cupertino. Both build a `Text('Discover')` that is always in the tree. `app/lib/src/core/platform/adaptive_scaffold.dart` is a page-level `Scaffold`/`CupertinoPageScaffold`; it cannot remove the shell's nav bar.

   Direct proof from the test itself: line 262 does `tester.tap(find.text('Discover').first)` while sitting on a *pushed team-page route inside the Profile branch*, and the suite is reported green on device (commit b0994c5). So `find.text('Discover')` demonstrably matches on any shell screen, pushed sub-routes included.

3. `settle` (lines ~30-42) is `for (i<40) { await pumpAndSettle(400ms); if (until.evaluate().isNotEmpty) return; }` — it evaluates *after the first pump*, so `settle(tester, find.text('Discover'), label: 'back_to_feed')` at line 275 returns on iteration 0 regardless of whether the composer popped. It is a ~1-frame delay, not a navigation wait.

4. The two surviving assertions (lines 279-280) are `findsNothing` on `'PostgrestException'` and `'row-level security'`. `app/lib/src/core/ui/human_error.da

---

## 11. [MEDIUM] The new match-date floor in discover_posts silently hides posts the composer happily creates
- **dimension**: sql
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707160000_posts_expire.sql`:80

**Failure scenario**

At 16:00 a user opens New post, taps the date chip, picks today, and dismisses the time picker. `new_post_composer.dart:64` defaults the hour to 9 when `time` is null, so `_matchAt` = today 09:00. The composer does no future-date validation, `createPost` never sends `_expires_at`, so `create_looking_for_post` stores `match_at` = today 09:00 and `expires_at` = tomorrow 09:00 (not expired). The post inserts fine, `context.pop()` runs, the user sees the composer close as if it worked. But the new feed predicate `and (p.match_at is null or p.match_at >= now() - interval '6 hours')` evaluates 09:00 >= 10:00 as false, so `discover_posts` drops the row for every caller including the author. The ad is invisible from the instant it is created, with no error and no indication anywhere except a 'My posts' entry that still reads status 'open'. The picker also sets `firstDate: now.subtract(const Duration(days: 1))` (new_post_composer.dart:56), so choosing yesterday is a one-tap route to the same silently-dead post.

**Why it is real**

The floor is new in this migration and is deliberately applied 'whatever the caller asked for', i.e. independent of any client filter. The composer was not updated to match it: I read `_pickWhen` and `_submit` and there is no check that `_matchAt` is in the future, no warning, and no server-side rejection either — `create_looking_for_post` accepts a past `match_at` and returns an id. So the write path and the read path now disagree about what a valid post is, and the user gets a success signal for a post nobody will ever see.

**Skeptic could not refute it**

NOT REFUTED (mechanism confirmed), but the finder's arithmetic is wrong and the trigger needs restating.

What I verified in the code (all opened, not inferred):

1. The floor exists and is unconditional. `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707160000_posts_expire.sql:80` — `and (p.match_at is null or p.match_at >= now() - interval '6 hours')`, sitting above the optional `_on_or_after` predicate on line 83. It is applied for every caller, author included. `grep` over `backend/supabase/migrations/` shows 20260707160000 is the NEWEST definition of `discover_posts` (earlier ones: 20260616203401, 20260617120500, 20260617130200, 20260702170200, 20260706111200, 20260707130600), so nothing later relaxes it.

2. No write-side guard anywhere. `create_looking_for_post` (same file, lines 34-41) inserts `_match_at` unchecked and sets `expires_at = coalesce(_expires_at, _match_at + interval '1 day', now() + interval '14 days')` — a post dated yesterday still gets a *future* expires_at, so the expiry predicate does not catch it; only the new match-date floor does. `grep -rn "match_at" backend/supabase/migrations/` shows no CHECK constraint and no trigger on `looking_for_posts.match_at`.

3. Client has no guard either. `app/lib/src/features/discover/presentation/new_post_composer.dart:56` `firstDate: now.subtract(const Duration(days: 1))` (yesterday is selectable); `:64-65` `time?.hour ?? 9` fabricates 09:00 when the time picker is dismissed; `_post()` (`:88-128`) validates only flair and team, then `context.pop()` on success. `discover_repository.dart` `createPost` never sends `_expires_at`.

4. No feedback afterwards. `my_posts_screen.dart` renders the raw `status` chip ('open') plus Mark filled / Can

---

## 12. [MEDIUM] set_team_member_role's last-captain guard counts departed captains, so a team can be stripped of its last captain
- **dimension**: left_at
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260707120000_team_members_update_lockdown.sql`:74

**Failure scenario**

Ravens XI has captains A and B plus admin D. B leaves; leave_team's own guard counts `where ... role = 'captain' and left_at is null` = 2, allows it, and stamps B's left_at. A is now the only active captain. D calls set_team_member_role(A's membership, 'player'). That guard is `select count(*) from team_members where team_id = _team and role = 'captain'` with NO left_at filter, so it counts A + departed B = 2, passes, and demotes A. The team now has zero active captains. D can then call leave_team on themselves: leave_team's guard only fires for `_row.role = 'captain'`, and D is 'admin', so it does not fire. D departs and the team has zero rows satisfying is_team_admin - nobody can add a player, mint an invite, approve a join request, edit or delete the team, or create a match in its name. That is exactly the unrecoverable state leave_team's own comment says it exists to prevent. This migration's header explicitly moved the guard server-side because the UI copy "was advisory only", so the server version is the authority - and it is now wrong. (The client-side guard in team_page_screen.dart:374-382 counts the roster, which DOES filter left_at, so it is the RPC, reachable directly over PostgREST by any authenticated user, that is broken.)

**Why it is real**

Compared the two guards directly: 20260707180000_leave_team.sql lines 78-81 has `and left_at is null`; 20260707120000_team_members_update_lockdown.sql lines 73-76 does not. Read is_team_admin's new definition (leave_team.sql lines 37-46) to confirm a departed row grants nothing, and leave_team lines 76-83 to confirm its captain guard is scoped to `_row.role = 'captain'` only, leaving an 'admin' free to exit. Before left_at existed the demoted/removed captain's row was deleted, so the unfiltered count was correct; the tombstone is what inflates it.

**Skeptic could not refute it**

NOT REFUTED — the code is exactly as described and no other guard closes it.

Verified in the files:
1. backend/supabase/migrations/20260707120000_team_members_update_lockdown.sql:73-77 counts `from public.team_members where team_id = _team and role = 'captain'` with NO `left_at` filter. backend/supabase/migrations/20260707180000_leave_team.sql:78-81 has the same guard WITH `and left_at is null`. The asymmetry is verbatim.
2. `left_at` was introduced by 20260707180000_leave_team.sql, a NEW file in this fix run (git diff --stat 65e2029..HEAD). `grep -rn left_at backend/supabase/migrations/` returns hits in that file only — the older lockdown guard was never updated for the new tombstone. Classic missed-callsite regression introduced by the reviewed diff.
3. leave_team stamps left_at without changing role (line 100), so a departed captain's row remains role='captain' and inflates the unfiltered count. The tombstone (rather than a hard delete) requires the leaver to have match history (line 99), which the scenario supplies.
4. leave_team's exit guard is scoped to `_row.role = 'captain'` (line 78), so an 'admin' can walk out unguarded — confirmed.
5. Two captains are possible: team_members (20260615140501) has only a partial unique index on (team_id, profile_id); no uniqueness or count constraint on captain, and set_team_member_role has no guard against promoting a second captain. `grep "create trigger"` shows the only trigger on the table is team_members_immutable_identity_trg (team_id/profile_id only) — nothing enforces a captain count.
6. The end state is genuinely unrecoverable: is_team_admin requires `left_at is null` (leave_team.sql:36-45); every membership-insert path grants only 'player' (accept_invite → team_invites_multiuse.sql:46; respond_join_request → team_join

---

## 13. [MEDIUM] transfer_scorer will hand live scoring rights to a player who was removed from the team
- **dimension**: left_at
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260617121000_transfer_scorer.sql`:34

**Failure scenario**

Ravens XI's captain removes X for tampering with the scorecard; X has played, so leave_team stamps left_at and X's row survives. A Ravens match is live and Y is the scorer. Y calls transfer_scorer(match, X). The eligibility check is `exists (select 1 from team_members tm where tm.profile_id = _new_scorer_id and tm.team_id in (_m.team_a_id, _m.team_b_id))` with no left_at filter, so X's tombstone satisfies it and matches.scorer_id becomes X. Every scorer-gated RPC keys off is_match_scorer(match_id), which reads matches.scorer_id - not team_members - so X can now record_ball, edit_ball, set_result and delete the match for a team that expelled them. The error message the guard raises, 'the new scorer must be a member of either team', states the invariant the code no longer enforces.

**Why it is real**

Read transfer_scorer lines 32-40 in 20260617121000_transfer_scorer.sql; the exists() has no left_at predicate. Confirmed the app's picker (matchScorerCandidatesProvider, app/lib/src/features/scoring/data/match_providers.dart:192) WAS updated with `.isFilter('left_at', null)`, which shows the fix run intended departed members to be ineligible - but the RPC is directly callable over PostgREST by anyone who passes its authz branch (current scorer, or an admin of either team), so the client filter is cosmetic. The same unfiltered pattern is in add_squad_member's participant check (20260707130200_add_squad_member_validation.sql:25-28), which lets a departed player be named in a brand-new squad.

**Skeptic could not refute it**

Could not refute; the defect survives verification.

VERIFIED IN CODE: transfer_scorer at HEAD (20260617121000_transfer_scorer.sql:34-38) checks `exists (select 1 from public.team_members tm where tm.profile_id = _new_scorer_id and tm.team_id in (_m.team_a_id, _m.team_b_id))` with no left_at predicate. `git grep -l "function public.transfer_scorer" HEAD -- backend/` returns only that one file, so there is no later redefinition.

NO GUARD ELSEWHERE: matches has no CHECK/trigger binding scorer_id to roster membership (20260616200301_matches.sql:6 is only a profiles FK). is_match_scorer (20260616200401:8-11) reads matches.scorer_id alone and never touches team_members. record_ball (20260616201901:22), set_match_result (20260702120000:13) and edit_ball (20260707130300:41) each gate on nothing but is_match_scorer. Crucially, the same fix run revoked the alternative path: 20260707130100_revoke_direct_writes.sql:32-33 drops matches_update_scorer and revokes UPDATE on matches from authenticated, making transfer_scorer the ONLY write path to scorer_id — so this check is the sole gate, not defense-in-depth.

IT IS A REGRESSION THE FIX RUN CAUSED: before 20260707180000_leave_team.sql (commit 4a347c3, inside the reviewed range) every team_members row WAS a current member, so the unfiltered exists() was correct. That migration added left_at, stamps it on departure when the player has history (line 100), and its column comment says such rows "are not on the roster and hold no membership rights." It patched is_team_member and is_team_admin with `left_at is null`, and its own test 115-leave-team.test.sql:86-96 states the invariant: "departing must also END the access that membership granted, or 'leaving' is cosmetic." transfer_scorer queries team_members directly instead of via those h

---

## 14. [MEDIUM] opponentSearchProvider is keyed per keystroke on a keepAlive family, so a failed opponent search is cached for the rest of the session
- **dimension**: providers
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/data/match_providers.dart`:19

**Failure scenario**

Two captains set up a match together. Captain A opens Start a match -> Choose the opponent and types 'Dadar'. _OpponentSearchSheet does onChanged: (v) => setState(() => _query = v), so each keystroke mints a new family instance keyed by the record (query: 'D'|'Da'|'Dad'|'Dada'|'Dadar', excludeTeamId: 'a') and fires a search_opponent_teams RPC per keystroke. 'Dadar' returns nothing, so the sheet shows 'No team called "Dadar" - ... ask them to create their team on Pitch first.' Captain B creates 'Dadar CC' right there. Captain A closes the sheet, reopens it, types 'Dadar' again - the record key is structurally equal to the earlier one, the family instance is still alive (Riverpod 3.3.2 families default to isAutoDispose = false), so ref.watch returns the cached empty list without any network call. The same 'no team called Dadar' copy appears forever. Nothing in the app invalidates opponentSearchProvider, there is no pull-to-refresh on the sheet, and the empty-query key (the 'past opponents' list) is frozen the same way. Only an app restart clears it. The same non-disposal also means every intermediate prefix ever typed is retained for the process lifetime along with its result list.

**Why it is real**

Verified in the installed package that FutureProviderFamily defaults isAutoDispose to false (riverpod-3.3.2/lib/src/providers/future_provider.dart:189), so nothing here is ever collected or refetched. grep confirms opponentSearchProvider appears only at its definition, at start_match_screen.dart:318, and in test overrides - there is no invalidate call anywhere. The blocked flow is the app's primary CTA, and the failure mode is self-reinforcing because the error copy tells the user to do the exact thing that will not change the answer.

**Skeptic could not refute it**

Could not refute — every claimed mechanism is confirmed in the actual source.

1. Non-auto-dispose is real: app/lib/src/features/scoring/data/match_providers.dart:19 uses plain `FutureProvider.family`, and in the installed riverpod-3.3.2 `FutureProviderFamily`'s public constructor declares `super.isAutoDispose = false` (lib/src/providers/future_provider.dart). lib/src/core/builder.dart confirms only the `.autoDispose` builders pass `true`. Riverpod 3 did not flip families to auto-dispose by default.

2. Non-auto-dispose means never collected: lib/src/core/element.dart:1196-1204, `mayNeedDispose()` is a no-op unless `provider.isAutoDispose`. Losing the last listener does nothing; the cached AsyncData survives.

3. Reopening hits the same element: `FunctionalFamily.call(arg)` mints a new provider object, but `LegacyProviderMixin` (lib/src/core/provider/provider.dart:139-153) defines `==` as `other.from == from && other.argument == argument`, and Dart records have structural equality, so `(query: 'Dadar', excludeTeamId: 'a')` re-resolves to the cached element.

4. Nothing invalidates it: grep across all .dart files gives exactly 6 hits for `opponentSearchProvider` — the definition, one `ref.watch` at start_match_screen.dart:318, and 4 test overrides. No invalidate/refresh anywhere.

5. The dependency can't force a refetch: it watches `supabaseClientProvider`, a plain `Provider` returning `Supabase.instance.client` (lib/src/core/supabase/supabase_providers.dart), never invalidated.

6. Container lives for the process: lib/main.dart:19 is a single `const ProviderScope(child: PitchApp())`, never rekeyed, no observers or overrides.

7. No escape hatch in the UI: `_OpponentSearchSheetState.build` (start_match_screen.dart:317-383) puts results in a fixed `SizedBox(height: 320)` 

---

## 15. [MEDIUM] The opponent search sheet overflows on a 375x667 phone because the field autofocuses and the results box is a fixed 320px
- **dimension**: matchsetup
- **file**: `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/app/lib/src/features/scoring/presentation/start_match_screen.dart`:345

**Failure scenario**

On an iPhone SE / iPhone 8 class device (375x667 logical) - or any Android phone of similar height - the user taps "Choose the opponent" on Start-a-match. _OpponentSearchSheet has `autofocus: true`, so the software keyboard is up the moment the sheet appears. The sheet's Column is `mainAxisSize: min` with a hard `SizedBox(height: 320)` for the results, plus `bottom: MediaQuery.viewInsets.bottom + 20`. I reproduced this in a widget test (view 375x667 @3x, viewInsets.bottom = 260dp, i.e. a normal portrait keyboard) and got: "A RenderFlex overflowed by 53 pixels on the bottom." In a debug build that is the yellow/black stripe banner across the picker; in release the bottom 53px of the results list is clipped off-screen. On a 320x568 device or in landscape the shortfall is far larger.

**Why it is real**

Nothing in the sheet is scrollable except the inner ListView, and its height is pinned at 320 regardless of the viewport. The verification protocol for this fix run ran on the iPhone 17 simulator (852 tall), where 20+24+12+60+8+320+(keyboard+20) still fits, which is why it was not caught. The overflow is deterministic, not a race - I measured it with tester.takeException() after raising viewInsets.

**Skeptic could not refute it**

CONFIRMED by direct reproduction, not refuted.

Code check (start_match_screen.dart, all new in this fix run): `_OpponentField.onTap` calls `showModalBottomSheet(isScrollControlled: true)` -> `_OpponentSearchSheet`, whose build is a `Padding(top: 20, bottom: viewInsets.bottom + 20)` wrapping a `Column(mainAxisSize: min)` containing title / 12 / `TextField(autofocus: true)` / 8 / `SizedBox(height: 320, child: results...)`. Nothing outside the inner ListView scrolls, and the 320 is unconditional (the empty state gets it too).

Measured, not speculated. I wrote a widget test that pumps the real StartMatchScreen with the real AppTheme.material(), opens the sheet, and varies tester.view.physicalSize / viewInsets:
- Column intrinsic height measured 420.0 (title 24 + 12 + TextField 56 + 8 + 320).
- 375x667, viewInsets.bottom 260 -> "A RenderFlex overflowed by 53 pixels on the bottom" - the finder's number exactly.
- Threshold is keyboard > screenHeight - 460: 207 ok, 208 -> 1px overflow. So even the smallest iOS 4.7"/SE keyboard (216pt, QuickType bar off) overflows by 9px; the default (260pt with QuickType) by 53px.
- Zero results overflows identically (53px) because the SizedBox is fixed regardless of content.
- 360x640 Android with a 270dp IME -> 90px. iPhone SE landscape (667x375, ~162 keyboard) -> 247px; landscape is allowed (Info.plist lists LandscapeLeft/Right and there is no SystemChrome.setPreferredOrientations anywhere in lib).
- 393x852 (the iPhone 17 sim the fix run verified on) with a 336 keyboard -> no overflow, which explains the miss (and a simulator with a hardware keyboard reports viewInsets 0, hiding it entirely).

Refutation attempts that all failed:
- No app-level guard: main.dart and src/app.dart install no MediaQuery/builder wrapper; AppTheme sets no text

---

## 16. [MEDIUM] JOURNEY C: the display-name search assertion is satisfied by the search box the test just typed into
- **dimension**: tests
- **file**: `Projects/cricket-app/app/integration_test/user_journeys_test.dart`:291

**Failure scenario**

Make handle/name search return nothing at all (revoke the search RPC, or have it return an empty list). Line 288 types 'Scout $run' into the search TextField; line 291 then asserts `find.textContaining('Scout $run')` findsWidgets. `_MatchTextFinder.matches` (flutter_test/lib/src/finders.dart:1538-1542) matches `EditableText` by its controller text before any Text handling, so the search field itself is a match and the expectation passes on a screen showing zero results.

**Why it is real**

The reason string says 'search must find a player by display name', but the query string and the expected result string are the same literal, and the query string is guaranteed to be on screen in the input. The second search assertion at line 298 does not have this problem (the box then holds '@j$run', a different string), which is what masks the first one.

**Skeptic could not refute it**

CONFIRMED - I could not refute it. Three independent checks:

(1) The code says what the claim says, though the line numbers are shifted: in Projects/cricket-app/app/integration_test/user_journeys_test.dart the enterText is line 303 (`await tester.enterText(find.byType(TextField).first, 'Scout $run');`) and the assertion is lines 306-307 (`expect(find.textContaining('Scout $run'), findsWidgets, reason: 'search must find a player by display name');`), not 288/291.

(2) The finder mechanism is exactly as described. /Users/utkarsh/development/flutter/packages/flutter_test/lib/src/finders.dart:1538-1542 - `matches()` short-circuits with `if (widget is EditableText) return _matchesEditableText(widget);` before any Text/RichText handling, and `_matchesEditableText` (1573-1575) compares `widget.controller.text` against the pattern.

(3) I reproduced it empirically. A throwaway widget test (a TextField plus only a `Text('No players or teams found.')` empty state) typed 'Scout 123456' and asserted `find.textContaining('Scout 123456')` findsWidgets: it PASSED, and the matched-widget dump printed `[EditableText]` - the sole match was the input box. Probe file was deleted.

The scenario is reachable, not hypothetical. app/lib/src/features/discover/presentation/search_screen.dart holds the query in the TextField controller (lines 39-58) and renders `Text('No players or teams found.')` on zero rows (line 68) or `humanError(e, ...)` on failure (line 66) - in every one of those states the assertion still passes. Server-side, backend/supabase/migrations/20260706111000_search_handle.sql:11-12 makes display_name and handle two separate OR branches; with query 'Scout <run>' the handle ('j<run>') cannot match, so only the display_name branch could ever produce a real row. A regression dropp

---

## 17. [MEDIUM] 112-posts-expire assertion 4 does not exercise the match-date floor it is labelled for
- **dimension**: tests
- **file**: `Projects/cricket-app/backend/supabase/tests/112-posts-expire.test.sql`:49

**Failure scenario**

Delete the new line `and (p.match_at is null or p.match_at >= now() - interval '6 hours')` from `discover_posts` in 20260707160000_posts_expire.sql. All 6 assertions in 112 still pass. The `_past` post is created with `_match_at := now() - interval '1 day'` and no explicit expiry, so `create_looking_for_post` computes `expires_at = coalesce(null, match_at + interval '1 day', ...) = now()` exactly. `now()` is transaction_timestamp and constant inside the test's `begin ... rollback`, so the pre-existing filter `p.expires_at > now()` is already false and excludes the row on its own.

**Why it is real**

The migration documents three changes: the default expiry, the match-date floor, and the recency ordering. Assertion 4 ('a match that already happened is not in the feed') is the only one aimed at the floor, and it is fully satisfied by the expiry filter. No test in the suite creates a post whose match_at is in the past while expires_at is still in the future, which is the only shape that separates the two filters. The ordering change is untested as well.

**Skeptic could not refute it**

CONFIRMED — I could not refute it, and I reproduced it against the live local Postgres.

What I checked:

1. The arithmetic is exactly as claimed. `/Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707160000_posts_expire.sql:41` computes `coalesce(_expires_at, _match_at + interval '1 day', now() + interval '14 days')`. The `_past` fixture at `tests/112-posts-expire.test.sql:42-45` passes `_match_at := now() - interval '1 day'` and no `_expires_at`, so `expires_at = (now() - 1 day) + 1 day = now()` exactly. `now()` is `transaction_timestamp()` and the whole test file is one `begin ... rollback`, so this is deterministic, not timing-dependent.

2. Measured it. Running the fixture in a transaction against the local DB: `expires_at = 2026-07-27 16:50:08.425889+00`, `now() = 2026-07-27 16:50:08.425889+00`, `expires_at - now() = 00:00:00`, `expires_at > now()` = **f**. The pre-existing filter at migration line 77 `(p.expires_at is null or p.expires_at > now())` excludes the row on its own, before the new floor at line 80 is ever consulted.

3. Ran the whole test with the floor deleted. I rebuilt `discover_posts` verbatim minus the line `and (p.match_at is null or p.match_at >= now() - interval '6 hours')` and executed the full body of 112 against it. All six assertions still emit `ok`, including `ok 4 - a match that already happened is not in the feed`. So assertion 4 has zero power over the change it is labelled for.

Refutation angles I ruled out:
- No trigger or column default rewrites `expires_at`. `migrations/20260616203202_looking_for_posts.sql` defines the table with no triggers, and the new `set default (now() + interval '14 days')` never fires because `create_looking_for_post` inserts an explicit va

---

## 18. [LOW] Departed captains and admins keep receiving - and can read - their old team's join-request and guest-claim notifications
- **dimension**: left_at
- **file**: `Projects/cricket-app/backend/supabase/migrations/20260703190100_team_join_requests.sql`:49

**Failure scenario**

A was an admin of Ravens XI and left. Stranger S taps "Request to join" on the Ravens page. request_to_join's notification fan-out is `select tm.profile_id ... from team_members tm where tm.team_id = _team_id and tm.role in ('captain','admin') and tm.profile_id is not null` with no left_at filter, so A's tombstone still matches and A gets an inbox row reading "Sanjay Kulkarni asked to join Ravens XI" - disclosing to an ex-member who is asking to join a team they no longer belong to. notifications_screen.dart:61 routes 'join_request' to Routes.teamPage(refId), where A is not an admin, so the pending-request list is hidden by RLS and A lands on a stranger's team page with a Request-to-join button. The notification is unactionable and arrives forever. notify_claim_request (20260703150100_notification_triggers.sql, the `where tm.team_id = _team and tm.role in ('captain','admin')` fan-out) has the identical blind spot for guest-claim requests.

**Why it is real**

Read the fan-out in 20260703190100_team_join_requests.sql lines 44-51 and notify_claim_request in 20260703150100_notification_triggers.sql; neither filters left_at, while join_requests_select (line 20 of the same file) gates the actual data on is_team_admin, which now does filter left_at. That mismatch is precisely what makes the notification arrive but be unactionable. Confirmed the routing in app/lib/src/features/messages/presentation/notifications_screen.dart line 61.

**Skeptic could not refute it**

Could not refute — every link in the chain holds against the actual code.

1. The code says what is claimed. backend/supabase/migrations/20260703190100_team_join_requests.sql lines 44-50 fan out `select tm.profile_id ... from public.team_members tm where tm.team_id = _team_id and tm.role in ('captain','admin') and tm.profile_id is not null` with no left_at predicate. backend/supabase/migrations/20260703150100_notification_triggers.sql lines 63-65 (notify_claim_request) has the identical shape. I grepped all migrations: these are the only definitions of request_to_join and notify_claim_request; nothing recreates them with a filter.

2. The precondition is constructible. 20260707180000_leave_team.sql:100 does `update public.team_members set left_at = now()` and leaves `role` untouched, so a tombstone still reads role='admin'/'captain'. The last-captain guard (lines 78-84) blocks only the sole captain; a role='admin' member, or a captain when a second captain exists, leaves normally. Tombstoning (vs. outright delete) is chosen precisely when the person has match history — the common case for a captain/admin. The UI path is live: team_page_screen.dart:311 -> identity_repository.dart:78 -> rpc('leave_team'), reachable from the app-bar "Leave" action by any member.

3. The asymmetry is real and is new surface from this fix run. The same migration rewrote is_team_admin (lines 36-45) to add `and left_at is null`. join_requests_select (20260703190100:20) and guest_claims_select_requester_or_admin (20260615141301:15-20) both gate on is_team_admin, so the departed admin receives the notification but cannot read the underlying row. Before this run there was no left_at column and the old raw delete raised 23503 for anyone with history, so a departed-yet-notified admin was not previo

---

## 19. [LOW] 114 assertion 7 'the default list is bounded' passes with no limit at all
- **dimension**: tests
- **file**: `Projects/cricket-app/backend/supabase/tests/114-search-opponent-teams.test.sql`:70

**Failure scenario**

Remove `limit 25` from `search_opponent_teams`. Assertion 7 still passes. With `_query` null the function's CASE branch reduces to `p.last_played is not null`, and the fixture gives this user exactly one past opponent (Rivals CC); the 40 'Bulk Club' rows inserted just above have no matches, so they are filtered out by the join regardless of any limit. `count(*) = 1 <= 25` under every implementation.

**Why it is real**

Assertion 6 does test the cap, because the 40 bulk rows match by name. Assertion 7 claims to test the same cap for the no-query branch but the fixture never puts more than one row into that branch - it would need 26+ distinct past opponents to be capable of failing.

**Skeptic could not refute it**

NOT REFUTED - the claim is exactly right, and I confirmed it by mutation testing against the running local Supabase Postgres, not by reading alone.

Method: I copied /Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/tests/114-search-opponent-teams.test.sql verbatim and prepended a mutant `public.search_opponent_teams` byte-identical to the shipped one in /Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-app/backend/supabase/migrations/20260707170100_search_opponent_teams.sql EXCEPT the trailing `limit 25` was deleted. Ran it through `docker exec supabase_db_backend psql` inside a transaction, then rolled back.

Result:
  not ok 6 - the search result set is bounded   ('40' <= '25' failed)
  ok 7 - the default list is bounded
  DEFAULT LIST ROWS: 1
  SEARCH BULK ROWS: 40
  # Looks like you failed 1 test of 8

So assertion 6 genuinely kills the mutant; assertion 7 survives it. Assertion 7 (line 68-70) cannot distinguish a capped implementation from an uncapped one.

Why the fixture makes it vacuous, traced through the actual code:
- `create_team` (migrations/20260615140801_rpc_create_team.sql) inserts a `team_members` row for the creator, so opp@s.dev is a member of Mine XI, Rivals CC and Zebra Club - the `mine` CTE holds all three.
- The single `create_match(_mine, _riv, 20)` is the only row in `matches`, so the `played` CTE groups to exactly one row: Rivals CC.
- With `_query` null, `length(coalesce(trim(_query),'')) < 2` is true, so the CASE reduces to `p.last_played is not null` - i.e. only teams present in `played`. That is one team.
- The 40 `Bulk Club N` rows at lines 59-61 are a direct `insert into public.teams` with no `create_team`, no `team_members` row (I checked: there is no t

---


# REFUTED - do NOT act on these

- sql: A removed guest player's name is permanently unusable on that team, blocked by an invisible row - Refuted on reachability. The SQL half of the claim is accurate (add_guest_member at 20260703180000_guest_name_validation.sql:20-25 and add_match_guest at 20260703180100_match_guest_validation.sql:21-2

- sql: set_team_member_role's last-captain guard counts departed captains, so a team can be driven to zero admins - REFUTED (the mechanism is real in the text, but the consequence and reachability are not).

What checks out: set_team_member_role (20260707120000_team_members_update_lockdown.sql:74-75) counts `role='

- left_at: search_opponent_teams treats teams you have left as still yours, so the opponent shortlist is seeded from a stranger's match history - REFUTED. The mechanical premise is accurate — `mine` at Projects/cricket-app/backend/supabase/migrations/20260707170100_search_opponent_teams.sql:25-28 is `select tm.team_id from public.team_members t

- providers: Joining a tournament navigates to a tournament page whose overview provider was never invalidated - REFUTED — but not on the grounds I expected. The finder's Riverpod mechanics are all correct; the scenario is unreachable because the write that precedes the navigation can never succeed at HEAD.

Wha

- navigation: The `loading` gate returns a bare `/splash` and throws away `next`, so the invite/join link is still lost across sign-in (the fix does not fire in the real flow) - REFUTED — I reproduced the exact sequence against the real `onboardingRedirect` + a real go_router 17.3.0 and the bounce does not happen.

What the code actually does (files opened):
- `app/lib/src/fe

- matchsetup: Search sheet issues one unindexed RPC per keystroke and flashes the results back to a skeleton each time - The code literally says what the finder quotes, but the claim does not survive as a defect.

Verified as stated:
- start_match_screen.dart:342 `onChanged: (v) => setState(() => _query = v)` — no debou

- matchsetup: The new matches.overs_limit constraint can permanently brick a tournament, because create_tournament has no equivalent guard - REFUTED. The factual premises check out, but the conclusion ("permanently brick", "stuck in 'setup' forever") is false, and the proposed guard would not close the hole anyway.

What is true:
- /Users/

- matchsetup: "Teams must be different" is enforced only in the Flutter client - create_match and the matches table both accept team_a = team_b - The code facts are accurate but the finding fails the reachability/impact bar.

VERIFIED AS CLAIMED: 20260707170000_match_overs_sane.sql's create_match checks is_team_admin, overs 1-100, balls_per_ove

- matchsetup: search_opponent_teams treats teams the caller has left as still theirs when building the default opponent list - REFUTED — the text of the claim is accurate but it describes intended behaviour, and the stated failure scenario is not what the code produces.

What is true: `/Users/utkarsh/pinto/pinto/.claude/workt

- tests: JOURNEY A has no assertion that can fail; the tournament 'CRITICAL' step is conditional and unverified - REFUTED — primarily on scope, secondarily on the merits.

1) It is not the new surface. I extracted the JOURNEY A body from the base commit and from HEAD and diffed them (`git show 65e2029:.../user_jo

- tests: JOURNEY K's tab loop has no positive assertion, so a broken tab passes - REFUTED. I opened every file the claim depends on.

**1. The central premise is factually wrong — Profile also dumps the raw error.**
The claim says "the two string checks are unfailable for every scr

- tests: navigation_dead_ends: 'every tile is inert' is vacuously true if no tiles render - REFUTED. I opened both files, ran the test, and empirically simulated the exact regression the claim names.

Files:
- /Users/utkarsh/pinto/pinto/.claude/worktrees/angry-banach-2ccd7e/Projects/cricket-

