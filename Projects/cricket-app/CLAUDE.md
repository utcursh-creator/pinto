# Cricket App ("Pitch") - Development Index & Protocol

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

## Build state (as of 2026-06-19)
- **Backend: 4 sub-projects COMPLETE, 251 pgTAP tests green** (59 migrations, 51 test files). Local-only.
  1. Identity & Teams; 2. Scoring Core (event-sourced fold); 3. Matchmaking & Discovery (PostGIS + DMs); 4. Frontend-prep (flair, transfer_scorer, anon viewing, wagon hint) + post attachments (photos/link + Storage bucket).
- **Flutter frontend (sub-project 5): foundation + slices 2,3,4,5 DONE; attachments DONE. 27 widget tests green, analyze clean. Builds + runs on iOS sim AND Android apk.**
  - s1 Foundation: Riverpod (manual providers) + go_router + supabase_flutter; platform-adaptive 3-tab shell (Discover/Matches/Profile); onboarding gate (AuthGate); dev-auth shim.
  - s2 Identity: Profile/Edit/My teams/Create team/Team page+roster.
  - s3 Discover (headline): geo feed + flair filters + composer (flair + photos + link) + post detail+replies + realtime DMs + my-posts + location.
  - s4 Scoring: match-setup wizard (teams->squads->toss->openers) + live scoring console (run pad/extras/wicket/undo, fold-driven) + matches list.
  - s5 Live viewer (commit eb50318): read-only MatchViewerScreen (Live/Scorecard/Charts/Info) off compute_innings_state + `match:<id>` realtime re-fold, login-free; fl_chart Manhattan+worm; status-aware Matches nav + Watch action. Verified via integration_test (flutter drive on iOS sim vs live Supabase). NEW: `integration_test/` + `test_driver/` harness (screenshots -> /tmp/pitch_shots) is the no-computer-use way to drive the real app.
- **REMAINING**: slice 6 discover->match keystone bridge + gap screens (captain claim-inbox, find-live-matches, transfer-scorer UI, pending-invites) + fix go_router deep-link cold-start.
- **Known backend bug (being fixed in a separate worktree session)**: `record_ball` consecutive-over guard false-positives when a new over's first ball is a wide/no-ball + same bowler continues. Do NOT duplicate that fix here.

## Document index (read the relevant one before touching its area)
Backend design+plan pairs (`Projects/cricket-app/`):
- `2026-06-11-identity-teams-design.md` / `2026-06-12-identity-teams-backend-plan.md`
- `2026-06-16-scoring-core-design.md` / `2026-06-16-scoring-core-backend-plan.md`
- `2026-06-16-matchmaking-discovery-design.md` / `2026-06-16-matchmaking-discovery-backend-plan.md`
- `2026-06-17-frontend-prep-backend-design.md` / `-plan.md` (SP4: flair/transfer/anon/wagon)
- `backend/README.md` - the canonical backend reference (all 4 sub-projects + attachments + PostGIS/RLS rules).
Frontend design+plan (`Projects/cricket-app/`):
- `2026-06-17-flutter-foundation-design.md` / `-plan.md` (s1; has the verified version/idiom recipe).
- `2026-06-17-flutter-identity-ui-plan.md` (s2)
- `2026-06-17-flutter-discover-ui-plan.md` (s3)
- `cricheroes-frontend-map.md` - the ~55-screen nav map + 6 open decisions + anti-clone principles.
Memory: `.claude/context/memory/work_status.md` (detailed running log - the per-turn truth), `learnings.md` (reusable gotchas), `user_preferences.md`.

## Run / build / test / seed (copy-paste)
Env (prepend to bash):
`export PATH="$HOME/development/flutter/bin:/opt/homebrew/bin:$PATH"; export LANG=en_US.UTF-8; export JAVA_HOME=/opt/homebrew/opt/openjdk@17`
- Local Supabase: `cd Projects/cricket-app/backend && supabase start` (OrbStack must be up). DB at 127.0.0.1:54322. `supabase status` for keys.
- pgTAP: `cd backend && supabase db reset && supabase test db`. **`db reset` WIPES seeded demo data - re-seed after (see below).**
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

## Subagent/workflow note
Direct `Agent` tool dispatch is billing-blocked ("1M context usage credits"); **Workflow-tool agents work** - use them for research/verification (versions, APIs, adversarial review), not for writing interdependent Flutter code (build that directly, controller-TDD).
