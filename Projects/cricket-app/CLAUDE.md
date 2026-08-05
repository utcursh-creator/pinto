# Cricket App ("Pitch") - Development Index & Protocol

> ## ⚠️ CURRENT STATE - 2026-08-05
> **Three whole-system reviews have been run and all three are CLOSED.** The
> "Build state" section below describes 2026-06-27 and is historical.
>
> * `2026-07-07-penetration-review.md` (100 findings) - worked unit by unit.
> * `2026-07-28-review2-findings.md` + `2026-08-05-review2-audit.md` - 87/87:
>   84 fixed, 1 closed later, 1 user-only, 1 deferred with a reason (66,
>   tournament_overview's triple fold), 0 open.
> * `2026-08-05-review3-findings.md` - 23/23: 22 fixed, 1 REFUTED with evidence
>   (16 - pull-to-refresh does fire on Watch live; a vertical ListView with no
>   controller is `primary`, so it gets AlwaysScrollableScrollPhysics).
>
> Gates as of 2026-08-05, all verified against a database built FROM SCRATCH by
> `supabase db reset` (not an incrementally patched one):
> **pgTAP 950 tests / 147 files, 459 widget tests on both platforms, 9 device
> journeys on the iOS simulator, flutter analyze clean.**
>
> EVERYTHING IS LOCAL. The hosted backend is 8 migrations behind
> (20260805140000 .. 20260805210000) and the push needs the user's explicit go.
> Other user-only actions are listed in `oauth-provisioning.md` and in
> `.claude/context/memory/work_status.md`.
>
> Next, when the user picks: a review #4 over everything since workflow
> `wf_9b84f4f2-5c0` (fix its verdict join first - join by INDEX, not by title
> string, or every finding returns "no verdict returned" again), or the
> push-notifications scaffold, which is still genuinely unbuilt.

**READ THIS FIRST every iteration.** It is the single source of truth for the cricket-app build.
After compaction, read this file top-to-bottom, then skim the doc index below before doing anything.
Re-read it after each slice so you stay on track and don't build the wrong thing.

## What this is
CricHeroes-inspired iOS+Android cricket app. Headline = **geo-matchmaking** (post "looking-for"
ads, nearby players/teams discover + reply + DM), plus **full ball-by-ball scoring** + CricHeroes-style
**team management**. Solo builder (the user). Stack: **Flutter** (one codebase, platform-adaptive
Cupertino/Material) + **Supabase** (Postgres+RLS+Realtime+Storage). Brand accent teal `#0F6E56`
(deliberately NOT CricHeroes red).

## Where things live (paths, relative to repo root = this worktree)
- Backend (Supabase): `Projects/cricket-app/backend/` (`supabase/migrations`, `supabase/tests` pgTAP, `seed.sql`, `README.md`).
- Flutter app: `Projects/cricket-app/app/` (feature-first `lib/src/features/<feature>/`, `lib/src/core/`).
- All design/plan docs: `Projects/cricket-app/*.md` (indexed below).
- Memory (assistant): `.claude/context/memory/` (work_status.md = running log; learnings.md; user_preferences.md).

## Standing user rules (NON-NEGOTIABLE)
1. **No vibe coding** - spec -> plan -> TDD -> verify, every step. Use skills/superpowers fluidly.
2. **OSS / pre-built first**; don't hand-roll what a library/Supabase gives you.
3. **Backend before frontend** for any new capability.
4. **NEVER use em dashes** - use hyphens.
5. **Verify external/pricing/library claims** against current docs (use a Workflow), don't trust memory.
6. Honest calibration; concede when the user has better domain knowledge. The user pushes back hard - that's good.

## VERIFICATION PROTOCOL (the user enforced this; do NOT skip)
For every screen / wiring / integration, "verified" means ALL of:
1. `flutter analyze` clean.
2. Widget tests pass, run on **BOTH platforms** (`debugDefaultTargetPlatformOverride = TargetPlatform.iOS` AND android). Android is the test default and masks iOS-only bugs (e.g. the Cupertino "No Material widget" crash). Reset the override with `try/finally` (NOT addTearDown - invariant check runs before tearDowns).
3. **Actually run it on the iOS simulator** and look at the screen (screenshot) - including forms/inputs, as a human would use it. Don't claim done from analyze+tests alone.
4. **Live backend check**: hit the exact RPCs/queries the screen calls as the signed-in dev user (REST or in-app) and confirm real data round-trips.
5. Commit per slice with the Co-Authored-By trailer. Keep everything LOCAL (do not push/PR without explicit user go - task parked).

## Build state (HISTORICAL - as of 2026-06-27; see the handoff doc for current)
- **Backend: 6 sub-projects COMPLETE, ~396 pgTAP tests green (72 test files), and NOW HOSTED on Supabase.**
  1. Identity & Teams; 2. Scoring Core (event-sourced fold); 3. Matchmaking & Discovery (PostGIS + DMs); 4. Frontend-prep (flair, transfer_scorer, anon viewing, wagon hint) + post attachments; 5. **Player stats** (re-fold: compute_innings_cards + player_career_stats / player_recent_form / player_public_profile, anon-safe; commit c225ec5); 6. **Tournaments** (groups round-robin -> top-2/group -> semifinals -> final; tournament_matches join table reuses the scoring engine; tournament_standings with the ICC NRR all-out full-quota rule; generate_group_fixtures / generate_playoffs / advance_playoffs / tournament_leaderboard / match_potm / tournament_overview; commits 89bbce0..0d5be60).
- **HOSTED (2026-06-27): Supabase ref `ocejkqihgiinonpyafhl`** (https://ocejkqihgiinonpyafhl.supabase.co). All 72 migrations pushed (`supabase link --project-ref ocejkqihgiinonpyafhl` + `supabase db push` with SUPABASE_ACCESS_TOKEN in `backend/.env.hosted` gitignored). Anonymous sign-ins ON; dev@pitch.local + other@pitch.local seeded. App reaches hosted via `flutter ... --dart-define-from-file=hosted_defines.json` (`app/hosted_defines.json` gitignored: SUPABASE_URL + anon key + GOOGLE_WEB_CLIENT_ID). Default (no flag) = local 127.0.0.1. Verified end-to-end on the iOS sim (integration_test/hosted_smoke_test.dart). HOSTING GOTCHAS: Management API (api.supabase.com) needs a browser User-Agent or 403s (Cloudflare 1010); our migrations grant only authenticated/anon NOT service_role -> seed via the Management API query endpoint (runs as postgres); the anon JWT works as supabase_flutter `publishableKey`.
- **GAP-CLOSING (post-Stats, all verified on iOS sim + committed): corrections UI (ball log edit/insert/delete, 7e989a6), home-base location (set_my_location persist + my_home_location read, b4bd6f1), team invites (create_team_invite + /invite/:token, 4e4d141), profile/team photo upload (avatars bucket, 796e397).** These closed the dangling-RPC findings from an honest whole-app audit.
- **Tournaments FRONTEND DONE (3813447 data layer, 6ae0ff3 screens):** list + create (Matches tab), organizer manage (status-driven: groups->generate fixtures->score via console->generate/advance playoffs), public `/tournament/:id` (top-level login-free, 4 tabs Table/Fixtures/Bracket/Leaders from one tournament_overview call, champion banner), POTM on match viewer. CricHeroes-reverse-engineered (research doc + 2 approved mockups). 14 widget tests; verified on iOS sim (tournaments_walkthrough_test).
- **Player stats FRONTEND DONE (commit 0ff9f4f)**: login-free `/player/:id` screen (batting/bowling cards + fielding line + last-5 form strip + '-' for undefined ratios + empty state), wired from Profile "My cricket" + team roster rows. Verified on iOS sim.
- **Flutter frontend (sub-project 5): foundation + slices 2,3,4,5 DONE; attachments DONE. 27 widget tests green, analyze clean. Builds + runs on iOS sim AND Android apk.**
  - s1 Foundation: Riverpod (manual providers) + go_router + supabase_flutter; platform-adaptive 3-tab shell (Discover/Matches/Profile); onboarding gate (AuthGate); dev-auth shim.
  - s2 Identity: Profile/Edit/My teams/Create team/Team page+roster.
  - s3 Discover (headline): geo feed + flair filters + composer (flair + photos + link) + post detail+replies + realtime DMs + my-posts + location.
  - s4 Scoring: match-setup wizard (teams->squads->toss->openers) + live scoring console (run pad/extras/wicket/undo, fold-driven) + matches list.
  - s5 Live viewer (commit eb50318): read-only MatchViewerScreen (Live/Scorecard/Charts/Info) off compute_innings_state + `match:<id>` realtime re-fold, login-free; fl_chart Manhattan+worm; status-aware Matches nav + Watch action. Verified via integration_test (flutter drive on iOS sim vs live Supabase). NEW: `integration_test/` + `test_driver/` harness (screenshots -> /tmp/pitch_shots) is the no-computer-use way to drive the real app.
  - s6 (commits 5a1c363..b8549aa): 6a keystone discover->match bridge (team_seeking_opponent post -> "Propose a match" -> wizard pre-seeded opponent); 6b Watch-live list (status-gated, login-free); 6c transfer-scorer UI; 6d guest-claim flow ("This is me" roster + captain claim-inbox); 6e deep-link fix (public viewer = TOP-LEVEL `/watch/:id` + `onboardingRedirect()` public bypass); 6f discover feed refreshes on auth change. 50 widget/unit tests; bridge + find-live verified on sim via integration_test/slice6_walkthrough_test.dart.
- **Frontend slices 1-6 feature-complete for the v1 loop** (find -> form -> play -> score -> watch). DEFERRED: pending-invites inbox (token/link invites, no natural addressed list); external URL-scheme/universal-link registration (router handles deep /watch; platform config separate); anon Discover sign-in prompt (in a separate worktree task).
- **Known issues handled in separate worktree sessions (do NOT duplicate here)**: (1) backend `record_ball` consecutive-over guard false-positive on new-over wide/no-ball; (2) anon Discover tab shows raw discover_posts 403 -> needs a sign-in prompt.

## Document index (read the relevant one before touching its area)
Backend design+plan pairs (`Projects/cricket-app/`):
- `2026-06-11-identity-teams-design.md` / `2026-06-12-identity-teams-backend-plan.md`
- `2026-06-16-scoring-core-design.md` / `2026-06-16-scoring-core-backend-plan.md`
- `2026-06-16-matchmaking-discovery-design.md` / `2026-06-16-matchmaking-discovery-backend-plan.md`
- `2026-06-17-frontend-prep-backend-design.md` / `-plan.md` (SP4: flair/transfer/anon/wagon)
- `2026-06-23-stats-design.md` / `2026-06-23-stats-backend-plan.md` (Stats sub-project - BUILT end-to-end, backend c225ec5 + frontend 0ff9f4f; re-fold-per-innings approach)
- `2026-06-25-tournaments-design.md` / `2026-06-25-tournaments-backend-plan.md` (Tournaments sub-project #6 - BUILT end-to-end; groups->semis->final; tournament_matches join table reuses the scoring engine) + `2026-06-25-cricheroes-tournaments-research.md` (the reverse-engineering gap-matrix) + `2026-06-27-tournaments-frontend-plan.md` (6 frontend slices, all done).
- `backend/README.md` - the canonical backend reference (all 6 sub-projects + attachments + PostGIS/RLS rules).
- `oauth-provisioning.md` - the credential-boundary checklist (hosted Supabase, Google/Apple OAuth clients, Info.plist, etc.) + a "Concrete values" section (package ids, debug SHA-1, web client id, project ref). HOSTING is DONE; remaining = Android/iOS Google clients + the deferred Apple/push/store items.
Frontend design+plan (`Projects/cricket-app/`):
- `2026-06-17-flutter-foundation-design.md` / `-plan.md` (s1; has the verified version/idiom recipe).
- `2026-06-17-flutter-identity-ui-plan.md` (s2)
- `2026-06-17-flutter-discover-ui-plan.md` (s3)
- `cricheroes-frontend-map.md` - the ~55-screen nav map + 6 open decisions + anti-clone principles.
- **`2026-07-01-master-issue-map.md`** - the 94-issue defect map + 8-slice rebuild plan (that rebuild is DONE).
- **`2026-07-05-final-done-audit.md`** - the 10-agent audit that rejected the first "done" claim.
- **`2026-07-07-penetration-review.md`** - THE 100-finding adversarial review (12 fronts, run twice, skeptic-verified) + synthesis with the release gate and fix order.
- **`2026-07-07-fix-run-handoff.md`** - the review-#1 fix run's handoff. HISTORICAL as of 2026-08-05: it predates reviews #2 and #3, so its "remaining" list and its test counts are stale. Its gotchas are still good.
- **`2026-08-05-review2-audit.md`** - the 87-finding disposition for review #2 (what was fixed, refuted, deferred, user-only).
- **`2026-08-05-review3-findings.md`** - review #3's 23 findings, each with its disposition recorded inline under FIXED SO FAR / REFUTED.
Memory: `.claude/context/memory/work_status.md` (detailed running log - the per-turn truth), `learnings.md` (reusable gotchas), `user_preferences.md`.

## Run / build / test / seed (copy-paste)
Env (prepend to bash):
`export PATH="$HOME/development/flutter/bin:/opt/homebrew/bin:$PATH"; export LANG=en_US.UTF-8; export JAVA_HOME=/opt/homebrew/opt/openjdk@17`
- Local Supabase: `cd Projects/cricket-app/backend && supabase start` (OrbStack must be up). DB at 127.0.0.1:54322. `supabase status` for keys.
- pgTAP: `cd backend && supabase db reset && supabase test db`. **`db reset` WIPES seeded demo data - re-seed after (see below).**
- **AFTER `db reset`, RESTART KONG: `docker restart supabase_kong_backend`.** db reset restarts auth/db/realtime/storage but NOT the Kong gateway, which keeps routing to the dead auth upstream and answers every `/auth/v1/*` call with `{"message":"An invalid response was received from the upstream server"}`. Every device journey then fails at sign-up, which reads exactly like an app bug. Probe it with a REST signup before blaming the code.
- Flutter: `cd app && flutter analyze && flutter test`. iOS build: `flutter build ios --simulator --debug`.
- iPhone 17 sim udid `23708F23-B0FA-48AC-97B2-69330802D156`. Launch: `xcrun simctl boot <udid>; open -a Simulator; xcrun simctl install <udid> build/ios/iphonesimulator/Runner.app; xcrun simctl launch <udid> dev.pitch.pitchApp`. Screenshot: `xcrun simctl io <udid> screenshot /tmp/x.png` then Read it.
- Demo login (dev-auth shim, prefilled): `dev@pitch.local` / `password123`.
- **Re-seed after any `db reset`** (creates dev+other users, profiles, Mumbai United team): admin API `POST /auth/v1/admin/users` (service_role bearer, email_confirm:true) then insert profiles/teams via `docker exec -i supabase_db_backend psql -U postgres -d postgres`. Service_role lacks table grants so seed via the DB superuser, not REST. Well-known local service_role/anon JWTs are stable demo keys (in work_status.md).
- iOS needs full Xcode (installed). Android SDK 36 via brew (no-sudo). `enable_anonymous_sign_ins=true` in config.toml (needs stack restart to take effect).

## Build-time gotchas (full detail in learnings.md)
- supabase_flutter 2.15: `anonKey` deprecated -> use `publishableKey`. `await rpc()` returns the list directly. record_ball returns table -> `.single()`. compute_innings_state -> Map.
- Realtime = Broadcast-from-database: `client.channel(name, RealtimeChannelConfig(private:true))` + `client.realtime.setAuth(token)` + `.onBroadcast(event:'INSERT', cb: payload['payload']['record'])` + teardown `removeChannel`. NOT onPostgresChanges.
- AdaptiveScaffold wraps the Cupertino body in `Material(type: transparency)` so Material widgets work on iOS.
- Riverpod 3.x: `.value` not `.valueOrNull`; `Override` type not nameable in tests (inline overrides); manual Notifier/AsyncNotifier (no codegen); riverpod_lint via top-level `plugins:` block.
- Android compileSdk pinned to 36 (app + plugin modules via subprojects afterEvaluate guard).
- go_router StatefulShellRoute does NOT cold-start deep into a non-default branch (only in-app push works) - fix in slice 6 for share/deep links.
- Postgres: changing a function's return type/signature needs DROP+CREATE; a `returns table` SRF errors in scalar context.
- Migrations are MANUALLY timestamped (the slow `supabase migration new` truncates writes). One object per file.

## Fix-run gotchas (2026-07-07 - full detail in the handoff doc + learnings.md)
- **Riverpod: a SYNC provider must never watch an ASYNC provider.** The first widget watch during build flushes the async ancestor, which notifies the sync dependent, which calls invalidateSelf -> setState MID-BUILD. Widgets may watch async providers; intermediate sync providers may not. Crashed Discover on every open; took 3 attempts because there were 3 instances. `flutter analyze` + widget tests passed for all three broken versions - only the device caught it.
- **When a crash moves to a new line after your fix, you fixed an INSTANCE, not the class.** Enumerate the shape across the codebase before touching anything else.
- **`flutter build ios` error 74** -> `rm -rf build/ios` (stale dir + the `com.apple.provenance` xattr on files under `.claude/worktrees/`). A direct `xcodebuild -sdk iphonesimulator build` succeeding proves the app code is fine.
- **pgTAP: psql does NOT interpolate `:'var'` inside `$$`-quoting** - hence the old `(select id from public.X limit 1)` habit, which made guard tests catch the WRONG error and pass for the wrong reason. Use `format($$ ... %L ... $$, :'var')`. Prove a scoping fix by seeding a decoy row.
- **`create or replace function` with a new arity creates an OVERLOAD**, not a replacement -> ambiguous calls, PostgREST 300. `drop function <exact old signature>` first.
- **`integration_test` runs all tests in ONE process and supabase_flutter persists the session** - later journeys start signed in; reset first.
- **Verified UI labels** (do not guess): create-team button `Create`, guest CTA `Add guest player`, tournament submit `Create tournament`.

## Subagent/workflow note
Direct `Agent` tool dispatch is billing-blocked ("1M context usage credits"); **Workflow-tool agents work** - use them for research/verification (versions, APIs, adversarial review), not for writing interdependent Flutter code (build that directly, controller-TDD).
