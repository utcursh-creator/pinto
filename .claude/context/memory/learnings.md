---
type: memory
category: learnings
last_updated: 2026-06-27
---

# Learnings

## Persist workflow/audit outputs as project docs IMMEDIATELY (2026-07-06, cricket)
The final done-audit's full result (10 agents, per-issue evidence for 94 ids) lived only in a temp workflow output file; when the user asked "where is the audit? i don't see it" there was nothing in the repo to point at. Deliverables the user will want to read (audits, research syntheses, verdicts) must be written into the project's dated-doc convention (Projects/<proj>/YYYY-MM-DD-<name>.md, frontmatter + committed) in the SAME turn they are produced - the temp task output is an implementation detail, not a deliverable. Corollary: git status at milestones - the 94-issue master map itself sat untracked for days.

## pgTAP + basejump: capture uids BEFORE mutations that scrub metadata (2026-07-03, cricket)
basejump's tests.authenticate_as/get_supabase_uid look users up by `raw_user_meta_data ->> 'test_identifier'`. Any code under test that rewrites raw_user_meta_data (e.g. account anonymization setting it to '{}') silently breaks every LATER helper lookup for that user - the error is a confusing "User with identifier X not found" far from the cause. Pattern: `select tests.get_supabase_uid('x') as _uid \gset` FIRST, then assert against :'_uid' after the mutation. Related (same session): bulk-seeding OTHER users' profiles in a test needs `reset role;` first (RLS blocks inserts after authenticate_as). Also: supabase account deletion without an Edge Function = SECURITY DEFINER RPC deleting auth.users works, BUT profiles->auth.users cascades while domain tables may reference profiles WITHOUT cascade - so accounts with shared history must be ANONYMIZED (blank profile + scrub auth identity + ban) instead of deleted.

## Reverse-engineer the incumbent's CONSENT model, don't invent a gate (2026-07-02, cricket SEC-8)
When I flagged "an organizer can enroll a team without consent" I patched it with an over-strict gate (organizer must admin every team), which broke the real multi-team use case. The user pushed: "how is CricHeroes fixing this?" A research Workflow (verify against PRIMARY sources, flag inferences) showed CricHeroes does NOT gate the organizer or run a two-way approval queue - it flips consent to the TEAM: the organizer shares a tournament invite link / PIN and a team CAPTAIN opts their own team in (self-registration = consent). "Silent unilateral add of a stranger's team" was NOT primary-verified, so copying it would have been wrong. Lessons: (1) for a "how does X prevent this abuse" question, research the incumbent's actual mechanism before designing - don't reach for the first gate that closes the hole; (2) the fix often already exists as a primitive one level down - here our team_invites token (mint token -> admin redeems -> consent-by-redemption) lifted verbatim to tournament_invites, almost no new machinery; (3) the redeemer's is_team_admin check IS the entire consent boundary in a SECURITY DEFINER redeem RPC - never derive the entered team from the token, the caller names it and must own it; (4) keep organizer direct-add for teams they admin AND add the token path for strangers - two paths, like the incumbent. Adversarial-verify workflow output: a "high confidence" rating on a claim sourced only to an unfetchable YouTube description is overstated - the skeptic pass caught it.

## "Feature-complete dev build" != "made app" - calibrate explicitly (2026-06-19, cricket app)
When the cricket v1 loop was built+verified, the user asked "so everything is done, made for iOS+Android, FE+BE connected thoroughly?" The honest answer was NO, and overclaiming would have burned trust. The distinction to always draw for app builds: a verified DEV BUILD (runs locally, real round-trips against LOCAL Supabase, one platform actually run) is NOT a shippable product. The gap to "real app" is usually: (a) host/deploy the backend (local 127.0.0.1 is unreachable from a phone), (b) wire real auth (OAuth) - a dev email/password shim is not real login, (c) run+verify on BOTH real platforms (running iOS sim != Android verified), (d) store packaging (signing/icons/listings), plus whatever's intentionally out of scope. Name these gaps proactively; don't let "feature-complete" read as "done/shippable".

## Event-sourced denormalized snapshots need re-stamping after corrections (2026-06-23, cricket)
The cricket `deliveries` table stores a per-ball striker/non-striker snapshot, stamped correctly on the live append (record_ball) but left STALE by the correction RPCs (edit/insert/delete change downstream strike rotation). The authoritative fold (compute_innings_state) ignores the snapshot and re-derives, so the scorecard was always right - but ANY direct reader of the snapshot (ball-log, per-delivery stats, wagon-by-batter) would be wrong after a correction. Fix pattern (option b): a `restamp_innings_strike(innings)` function that re-runs the fold's exact rotation loop (stripped of aggregation) and UPDATEs the stored columns, called at the end of every correction RPC; plus column comments stating "any new mutation path must call this". Best TDD anchor: a corruption-repair test (manually corrupt the stamps -> restamp -> assert corrected) PLUS edit/insert scenarios with hand-computed expected facing batters. General lesson: a denormalized column in an event-sourced schema is a footgun unless EVERY write path maintains it; either re-derive on read (authoritative) or re-stamp on every mutation - never half-maintain.

## Derived per-player stats: re-fold + divergence-guard, don't flat-aggregate (2026-06-25, cricket Stats)
Career batting/bowling/fielding were built by RE-FOLDING each innings via a per-player generalization of the authoritative fold (`compute_innings_cards`, lifted from `compute_innings_state`), NOT by a flat SQL view over `deliveries.*`. Two reasons a flat view is wrong: (1) `record_ball` leaves `dismissed_player_id` NULL for bowled/caught/lbw/stumped (the fold attributes those to the on-strike striker), so flat `dismissed_player_id = player` undercounts most outs; (2) maidens/HS/BBI/50s/4w are inherently per-innings, not flat sums. The two folds are kept in lockstep by DIVERGENCE-GUARD assertions in the test (cards totals MUST equal compute_innings_state on a shared fixture) - the cheap insurance against the parallel folds drifting. Career RPC = SECURITY DEFINER + search_path='' + anon+authenticated, with the completed-status filter BAKED IN (anon can't reach setup/live data); identity rollup via `player_key = COALESCE(team_members.profile_id, id)` so a guest-claim re-keys history at read time with zero backfill. Compose a thin `player_public_profile` wrapper (identity + career + recent_form) so the frontend does ONE round-trip. Reusable PL/pgSQL gotchas hit: (a) Postgres `now()` is FIXED per transaction, so a pgTAP test asserting `created_at`-ordering (e.g. recent-form newest-first) must UPDATE distinct created_at values - rows created in one test all share the same now(); (b) `SELECT ... INTO var` sets the target to NULL when zero rows match, so a scratch `line` var is safe to reuse across batting/bowling/fielding extraction queries; (c) `jsonb_array_elements(x)` exposes its column as `value` - filter `where (value->>'k')::uuid = any(_members)`.

## Supabase migrations are versioned by the LEADING TIMESTAMP - duplicates silently break db reset (2026-06-25, cricket Tournaments)
Two migration files sharing the same leading timestamp (e.g. `20260625120000_home_location_read.sql` AND `20260625120000_tournament_enums.sql`) collide: the Supabase CLI keys applied migrations by that version number, so on a clean `supabase db reset` the SECOND file is treated as already-applied and SKIPPED. Symptom: the suite passed when I applied migrations incrementally to the live DB (both ran), but after `db reset` an enum/object from the skipped file was missing, cascading into "Bad plan: planned N tests but ran 0" for the dependent test + a truncated suite. Fix: every migration needs a UNIQUE leading timestamp; I renumbered the whole sub-project's migrations to a clean later block. Lesson: when manually timestamping migrations (we do, because `supabase migration new` truncates writes), grep `ls *.sql | sed 's/_.*//' | sort | uniq -d` for duplicates, and ALWAYS verify a new sub-project via a full `db reset && test db` (not just incremental psql apply) before trusting it.

## pgTAP: no inline `-- comment` on a `\gset` line (2026-07-02, cricket Slice 1)
`select public.create_team('C') as _c \gset  -- a team not in the match` FAILS: `\gset` parses the rest of the line as its optional prefix argument, so it eats the comment -> `\gset: extra argument "match" ignored` + `error: invalid variable name: "--_c"`, and the whole pgTAP file then reports `Wstat: 768 (exited 3)`. Put the comment on its OWN line above the `\gset`. (Same lowercase-alias family as the note below.)

## pgTAP: keep `\gset` alias names lowercase (2026-07-01, cricket Slice 1)
`select ... as _mA \gset` sets a psql variable named `_ma`, because Postgres FOLDS the unquoted column alias to lowercase. But psql variable *references* `:'_mA'` are case-SENSITIVE, so `:'_mA'` is unset and passes through literally -> `ERROR: syntax error at or near ":"` (and, in a pgTAP file, the whole test then reports `Wstat: 768 (exited 3) Tests: 0`). Fix: name `\gset` aliases in lowercase (or numeric: `_m1`, `_i1`) and reference them the same way. The existing tests all use lowercase aliases; a mixed-case one silently breaks.

## Programmatically copying a PL/pgSQL function body: anchor on "create or replace FUNCTION", not "create or replace" (2026-07-01, cricket Slice 1)
When generating a new fold/RPC migration by transforming an existing one with python/sed (`body = src[src.index('create or replace'):]`), anchor on the FULL phrase **`create or replace function`**. The source file's HEADER COMMENT frequently contains the bare phrase (e.g. `-- Return type unchanged -> create or replace (no drop needed).`), so `str.index('create or replace')` matches the COMMENT first and the output keeps a stray `create or replace (no drop needed).` line above the real definition -> `ERROR: syntax error at or near "(" (SQLSTATE 42601)` when `supabase db reset` applies it. Symptom is loud but non-obvious: the failing migration aborts db reset, so `supabase test db` then reports EVERY test as `(Wstat: 768 (exited 3) Tests: 0)` - a cascade, not a per-test failure. Diagnose by running `supabase db reset` alone and grepping for `ERROR`. (This is why the sed-transform approach still needs a full db-reset verification, same lesson as the duplicate-timestamp gotcha.)

## Seeded-data + provider-override tests gave FALSE confidence; the core loop was hollow (2026-06-27, cricket - HARD user feedback)
A friend cold-tested the release APK and the core loop fell apart: teams created but couldn't form a real Team-A-vs-Team-B match (opponent picker is a global dropdown, no "create opponent here", so both sides end up your own teams); named teams render as literal "Team A"/"Team B" (match_squads_screen.dart:68,75 and toss_openers_screen.dart:64,72 HARDCODE the labels and never fetch names; match_viewer falls back to 'Team A'/'Team B' when matchTeamNamesProvider returns empty); no remove-player; the looking-for post form lacks the fields a cricketer actually needs (ball-type, overs, optional contact) though the card shows ball/overs; the Location screen exposes raw lat/long text fields (19.07/72.87) which is meaningless to a user; "Need an opponent" rendered twice on the feed card. The user's verdict: "feels hollow, like a skeleton with huge gaps, you have not tested it nor developed it properly." FAIR. **Root lesson: my verification (provider-override widget tests + integration tests that SEED data via RPCs then assert a screen renders) structurally CANNOT catch whether a fresh user can BUILD the data through the UI.** Seeding team names directly + asserting the viewer shows them never exercised the setup screens that hardcode "Team A"/"Team B"; pre-seeded matches never tested "can you even create A-vs-B from scratch". **A single real cold playthrough (create team -> name it -> make A vs B -> score -> view) would have caught all of it.** Going forward: the acceptance test for any user-facing loop is a from-scratch human (or scripted-through-the-UI) playthrough that CREATES every entity via the UI, not seeded fixtures; placeholder literals ("Team A") in shipping UI are a red flag to grep for. Also: don't claim "verified on device" from booting to a screen - exercise the actual end-to-end task. [[supabase anonymous users top-level is_anonymous]] was a related fresh-launch-only miss.

## Flutter release-signed APK + native Google sign-in: the release SHA-1 needs its OWN Android OAuth client (2026-06-27, cricket)
Shipping a `flutter build apk --release` for friend-sharing (no Play Store): (1) Add a `signingConfigs.create("release")` to `android/app/build.gradle.kts` reading a gitignored `android/key.properties` (storePassword/keyPassword/keyAlias/storeFile); GUARD it with `if (keystorePropertiesFile.exists())` and fall back to the debug key in `buildTypes.release` so CI/fresh clones without the keystore still build (verified idiomatic + better than the flutter.dev snippet). Kotlin DSL: `import java.util.Properties; import java.io.FileInputStream` above `plugins{}`, `rootProject.file("key.properties")` resolves to android/ (one level above app/). No `storeType` field exists in Gradle - PKCS12-vs-JKS is fixed at keystore-creation. (2) Keytool: `keytool -genkeypair -keystore ~/pitch-release-keystore.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias <a> ...`; store it OUTSIDE the repo + back it up (losing it blocks app updates / is the Play upload key). (3) **A release build is signed with a DIFFERENT key than debug, so its SHA-1 is different -> Google sign-in fails on the release APK with `PlatformException(sign_in_failed, ApiException: 10)` (DEVELOPER_ERROR) until you create a SECOND Android-type OAuth client (same package, the RELEASE SHA-1) in Google Cloud.** An Android OAuth client holds exactly ONE package+SHA-1 (the SHA-1 field is single-value), so debug and release each need their own client; Play App Signing needs yet another (Google re-signs with its own key). None of these Android client ids go into the Supabase Google "Client IDs" field (token aud = the web serverClientId; the Android client only authorizes the app to Google at runtime). (4) Installing a release APK over a debug-signed one with the same package fails (signature mismatch) - `adb uninstall` first. (5) NO ProGuard/R8 keep-rules needed for google_sign_in v7 / supabase_flutter / device_info_plus / geolocator / share_plus / fl_chart as long as `minifyEnabled` is unset (R8 off by default); only if you opt into `isMinifyEnabled=true` does google_sign_in need `-dontwarn/-keep com.google.common.** + com.google.errorprone.annotations.**`. Verify the APK is actually release-signed: `apksigner verify --print-certs app-release.apk` -> should show `CN=Pitch App`, not "Android Debug". Verified via workflow wf_19ea631c-881.

## Supabase anonymous users: `is_anonymous` is a TOP-LEVEL claim, NOT in app_metadata (2026-06-27, cricket - real bug caught by running the fresh app)
The cricket app's `isAnonymousSession()` checked `session.user.appMetadata['is_anonymous'] == true`. That is ALWAYS false for a real anonymous user: Supabase puts `is_anonymous` as a TOP-LEVEL JWT claim (the gotrue `User` model parses it onto `User.isAnonymous`), and leaves `app_metadata == {}` for anon users. Verified directly against the hosted project by POSTing `/auth/v1/signup` with an empty body and decoding the response: `user.is_anonymous: true`, `user.app_metadata: {}`, JWT `is_anonymous: true` top-level, JWT `app_metadata: {}`. So the buggy check misclassified every anonymous user as a real signed-in user, and the onboarding gate routed them to `needsProfile` -> the "Create profile" screen instead of the `anonymous` -> Discover branch. Worse, the Google **sign-in screen was only reachable** via the "Sign in" prompt ON Discover/Profile, so a fresh-install user was dead-ended on a profile form with no way to sign in. **Fix: use the SDK property `session.user.isAnonymous`** (which reads the top-level claim) - other call sites already did. **Why it hid for so long:** every widget/router test OVERRIDES the gate (`authGateProvider`/`isAnonymousProvider`) so `isAnonymousSession` had NO direct unit test, and the public `/watch|/player|/invite|/tournament` deep links BYPASS the gate. The bug only surfaces on a real first-launch as a true anonymous user - which is exactly the path the "actually run the fresh app on the device" protocol exercised (this Android run). Lesson: pure helper functions that parse SDK/JWT shapes need their OWN unit tests against the REAL response shape (don't trust field-name memory: `app_metadata` vs top-level), because provider-override tests skip them entirely. Reusable: to construct a gotrue `Session` in a Dart test, `User.fromJson({id, app_metadata:{}, user_metadata:{}, aud:'authenticated', created_at:..., is_anonymous:true})!` then `Session(accessToken:'x', tokenType:'bearer', user: user)`.

## Hosting a Supabase backend (CLI push + Management API seeding) - gotchas (2026-06-27, cricket)
Took the cricket backend from local-only to HOSTED on the user's own Supabase project (ref `ocejkqihgiinonpyafhl`). Reusable gotchas:
- **`supabase db push` works with just `SUPABASE_ACCESS_TOKEN`** (a `sbp_...` personal token), no DB password needed: `supabase link --project-ref <ref>` then `supabase db push`. All 72 local migrations applied cleanly to the remote in order. The access token + URL live in a GITIGNORED `backend/.env.hosted`.
- **Our migrations grant DML only to `authenticated`/`anon`, NOT `service_role`** (a deliberate least-privilege choice from sub-project 1). Consequence on the hosted project: the service_role REST role got "permission denied for table X" when I tried to seed via PostgREST - same as the local-seeding gotcha. Fix: seed through the **Management API query endpoint** (`POST https://api.supabase.com/v1/projects/<ref>/database/query` with the access token), which runs raw SQL **as `postgres`** (bypasses grants + RLS), exactly like local `psql -U postgres`. Auth users still go through the GoTrue admin API (`/auth/v1/admin/users`).
- **api.supabase.com sits behind Cloudflare and 403s ("error 1010") a default urllib/python User-Agent.** Add a browser `User-Agent` header to every Management API request or it's blocked. (Hit this from a /tmp seeding script.)
- **The anon JWT works directly as supabase_flutter's `publishableKey`** init param (2.15 renamed `anonKey` -> `publishableKey`, but the value can still be the legacy anon JWT, not only an `sb_publishable_...` key). Hosted config delivered to the app via `--dart-define-from-file=hosted_defines.json` (gitignored): SUPABASE_URL + that anon key + GOOGLE_WEB_CLIENT_ID. No flag = local 127.0.0.1 defaults, so dev keeps working unchanged.
- **Watch for unicode corruption when hand-transcribing long keys.** A Cyrillic "Ф" had silently replaced a Latin sequence inside the pasted anon JWT (`ImFub24`->`ImФub24`), so base64-decode produced garbage and sign-in failed cryptically. Verify any pasted key with a `base64 -d` + `.isascii()` round-trip before trusting it.
- **Enabling anonymous sign-ins on hosted** is a config flip (`enable_anonymous_sign_ins`) via the Management API config endpoint; needed for the login-free public viewer/tournament/player deep links to work against hosted.
- Verify the whole thing with an integration_test pointed at hosted (`integration_test/hosted_smoke_test.dart`): asserts `SupabaseEnv.url` contains 'supabase.co', signs in dev, round-trips create_tournament + tournament_overview. This is the hosted analog of the local flutter-drive protocol.

## Supabase dashboard Google provider for the NATIVE idToken flow: Client IDs = web only, not Android (2026-06-27, verified wf_df81a5c5-7ec)
Configuring the Supabase Auth->Providers->Google screen for a Flutter app using the native flow (`signInWithIdToken`, google_sign_in v7 with `serverClientId` = the WEB client id):
- **The "Client IDs" (comma-separated) field must contain the WEB client id, and the WEB id alone is sufficient for BOTH Android and iOS native sign-in.** Because the app passes the web id as `serverClientId`, Google mints the id_token with `aud` = the WEB client id on every platform, and Supabase validates that `aud` against this list. **Do NOT add the Android OAuth client id** - it never appears as the token's `aud`. The Android client's only job is to authorize the running app to Google, matched by package + SHA-1; it must EXIST in Google Cloud but must NOT go in the Supabase field. (Adding the iOS client id IS required once you support iOS - Supabase's documented Flutter requirement - because the iOS client is referenced; web stays first.)
- **"Client Secret (for OAuth)" can be left EMPTY for a native-only app.** It's only used by the web browser-redirect flow (`signInWithOAuth`), which `signInWithIdToken` never exercises (no auth-code exchange). If the dashboard form refuses to Save without it, paste the web client's secret purely to satisfy the form - it stays unused.
- **"Skip nonce checks" should be ON** whenever you'll do native iOS Google: google_sign_in v7 exposes no nonce, so the app sends none; with the toggle OFF, iOS tokens fail nonce validation. It's SAFE to turn on even for an Android-only build (no nonce is sent, so nothing is validated). It does NOT affect Apple (Apple uses its own raw/hashed nonce pair).
- **"Allow users without an email" OFF** (Google always returns a verified email). **Callback URL** is read-only and unused by the native flow (only the web-redirect flow needs it registered as an Authorized redirect URI).
- The error this prevents: **"Unacceptable audience in id_token"** = the token's `aud` (the web/serverClientId) isn't in the Client IDs list. At Play Store release, the Play App Signing key changes the SHA-1, so add an Android OAuth client for the Play App Signing SHA-1 (a missing one breaks `google_sign_in` getting a token at all - a sign-in error, distinct from the audience error).
- This is dashboard-only config for the HOSTED project; `config.toml` (local stack) needs no google block - we use the dev email/password shim locally. (config.toml's `skip_nonce_check` lives under `[auth.external.apple]`, not google - don't confuse them.)

## Supabase Flutter OAuth in 2026: native idToken flow + google_sign_in v7 break (2026-06-23)
For Supabase + Flutter, the recommended mobile sign-in is the NATIVE provider-idToken flow (`auth.signInWithIdToken(provider, idToken, accessToken, nonce)`), NOT the external-browser `signInWithOAuth` (that's for web/desktop + Apple-on-Android, which needs the io.supabase.<x>://login-callback deep link). KEY GOTCHA: the Supabase Dart REFERENCE page for signInWithIdToken still shows google_sign_in **v6** code (`googleAuth.accessToken`) that does NOT compile against the current **v7** - in v7 you use `GoogleSignIn.instance` singleton, `initialize(clientId, serverClientId)`, `attemptLightweightAuthentication() ?? authenticate()`, then idToken from `user.authentication.idToken` (sync getter) and accessToken from `user.authorizationClient.authorizationForScopes(scopes) ?? authorizeScopes(scopes)` (the v7 authn/authz split). Apple: native via sign_in_with_apple with a raw nonce -> SHA256-hashed to Apple, raw to Supabase; name returned only on first auth. Native iOS Google needs "Skip nonce check" ON in the Supabase Google provider. OAuth code can be fully wired + gated (empty client IDs -> friendly error) without the user's credentials; the accounts (Google Cloud clients, Apple Dev, dashboard, Info.plist reversed-client-id, Apple entitlement) are the credential boundary.

## Don't construct a real SupabaseClient in a widget test - it leaks timers (2026-06-23)
A test fake that does `super(SupabaseClient(url, key))` fails with "A Timer is still pending even after the widget tree was disposed" - constructing a real SupabaseClient starts internal periodic timers (auth refresh / realtime heartbeat) that outlive the test. Fix: make the service an `abstract interface class` and have the test fake `implements` it directly (no client at all). General rule: inject collaborators behind an interface so tests never instantiate the live SDK client.

## Riverpod 3.x: NEVER call ref.read in State.dispose() (2026-06-19)
A `ConsumerState.dispose()` that calls `ref.read(someProvider)` throws `StateError: Using "ref" when a widget is about to or has been unmounted is unsafe` in Riverpod 3.x (ref relies on BuildContext, unsafe once deactivated). Caught by the slice-5 integration test (real app, realtime ON), but MISSED by the widget tests because they ran with `enableRealtime:false` so the dispose path that used `ref` was skipped. Fix: capture the dependency in a State field during init/subscribe (e.g. `_client = ref.read(supabaseClientProvider)`) and use the saved field in dispose(): `_client?.removeChannel(ch)`. Lesson reinforced: a screen with realtime/streams MUST be exercised in a real run (integration_test), not just enableRealtime:false widget tests - the teardown path only runs when realtime is on.

## Verify a running Flutter app WITHOUT controlling the desktop: integration_test + flutter drive (2026-06-19)
The user forbade computer-use / Simulator puppeting for verification. The right substitute is a Flutter `integration_test` driven by `flutter drive`, which boots the REAL app on the sim and taps through it programmatically against the live local Supabase - "using the app as a human would" with zero desktop control. Setup: add `integration_test: {sdk: flutter}` to dev_dependencies; `test_driver/integration_test.dart` calls `integrationDriver(onScreenshot: (name, bytes, [args]) { File('/tmp/pitch_shots/$name.png').writeAsBytesSync(bytes); return true; })`; `integration_test/<name>_test.dart` does `app.main(); await tester.pumpAndSettle(); ...` then `await binding.takeScreenshot('01_live')` (binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()). Run: `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/<name>_test.dart -d <sim-udid>`. Screenshots land in /tmp/pitch_shots for me to Read. This satisfies the "actually look at the screen + live round-trip" protocol non-invasively. To sign in mid-app, call `Supabase.instance.client.auth.signInWithPassword(...)` then pumpAndSettle in a retry loop until the target widget appears. NOTE: takeScreenshot needs `convertFlutterSurfaceToImage()` first on Android only (not iOS).
- **Supabase realtime leaves a heartbeat Timer that fails integration_test teardown**: a screen that subscribes to a realtime channel keeps a periodic heartbeat Timer alive; when the test tree unmounts, integration_test reports "pending timer" as a failure EVEN THOUGH all assertions + screenshots succeeded. Fix: at the end of the test, `await client.removeAllChannels(); client.realtime.disconnect(); await tester.pumpAndSettle();` before the framework tears down.

## Flutter test: reset debug overrides inline (not addTearDown), and offstage ListView children (2026-06-17)
`debugDefaultTargetPlatformOverride` (and other foundation debug vars) MUST be reset before the test BODY returns - the framework's invariant check runs after the body but BEFORE addTearDown callbacks, so `addTearDown(() => debugDefaultTargetPlatformOverride = null)` fails with "The value of a foundation debug variable was changed by the test." Use `try { ... } finally { debugDefaultTargetPlatformOverride = null; }` (resets on pass AND on assertion failure, avoiding the leak that cascades into the next test). Also: a tall screen's `ListView(children:[...])` lazily builds children, so a widget below the fold may be offstage/unbuilt - `tester.tap(find.text('Post'))` silently misses an off-screen button. Fix: `await tester.ensureVisible(finder)` before tapping, and assert with `find.text(x, skipOffstage: false)`.

## go_router StatefulShellRoute deep cold-start (2026-06-17)
go_router's StatefulShellRoute.indexedStack does NOT reliably honor an `initialLocation` that points DEEP into a non-default branch (e.g. cold-starting at '/matches/<id>/score' landed on the default '/discover' branch instead). In-app `context.push`/`go` to those routes works fine; only cold-start/deep-link entry is affected. Implication: deep links / share links / push-notification taps into non-default branches need explicit handling (not just initialLocation). For screenshot verification of a deep screen, prefer an integration_test that taps through, or temporarily make that screen a default route.

## Cupertino scaffold needs a Material ancestor for Material widgets (2026-06-17)
A platform-adaptive scaffold that renders `CupertinoPageScaffold` on iOS gives NO Material ancestor, so `TextField`/`ListTile`/`Chip`/`Divider`/ink widgets crash with "No Material widget found. TextField widgets require a Material widget ancestor" on iOS only. Fix: wrap the Cupertino branch's child in `Material(type: MaterialType.transparency, child: ...)` (invisible, just supplies the ancestor). CRITICAL TESTING LESSON: Flutter widget tests default to TargetPlatform.android (which uses a Material Scaffold = has Material), so Android-only tests PASS while iOS is broken. Always add a test that pumps adaptive screens under `debugDefaultTargetPlatformOverride = TargetPlatform.iOS`, and render the real screen on the iOS simulator before claiming verified. One AdaptiveScaffold fix repaired every form/list screen across slices 2-3 at once.

## Riverpod 3.x AsyncValue + local Supabase seeding (2026-06-17)
- Riverpod 3.x `AsyncValue<T>` exposes `.value` (T?), NOT `.valueOrNull` (removed -> compile error `undefined_getter`). Use `.value`.
- To seed the LOCAL Supabase stack for a demo: the `service_role` REST role has NO table grants in this project (migrations granted only `authenticated`/`anon`), so REST inserts as service_role 403. Seed via the DB superuser instead: `docker exec -i supabase_db_backend psql -U postgres -d postgres` (bypasses grants + RLS). Create the auth user via the GoTrue admin API (`POST /auth/v1/admin/users` with the service_role JWT as Bearer, `email_confirm:true`); the well-known local service_role/anon JWTs are stable demo keys. Verify the app's exact queries by signing in via `POST /auth/v1/token?grant_type=password` then hitting `/rest/v1/...` with that access_token (embedded selects like `team_members?select=role,teams(*)` work and respect RLS).

## Flutter Android compileSdk 36 + plugin modules (2026-06-17)
supabase_flutter pulls in device_info_plus transitively, which requires consumers to compile against Android API 36, but Flutter 3.44's default compileSdk is still 35 -> `flutter build apk` fails with "Dependency ':device_info_plus' requires ... compile against version 36" on a plugin module (passkeys_doctor). Fix BOTH: set `compileSdk = 36` in android/app/build.gradle.kts AND force it on plugin modules from android/build.gradle.kts: `subprojects { if (!state.executed) { afterEvaluate { extensions.findByName("android")?.let { (it as com.android.build.gradle.BaseExtension).compileSdkVersion(36) } } } }`. The `!state.executed` guard is REQUIRED: the flutter-generated `subprojects { project.evaluationDependsOn(":app") }` force-evaluates :app early, so an unguarded `afterEvaluate` on it throws "Cannot run Project.afterEvaluate when the project is already evaluated."

## Flutter foundation gotchas, 2026 stack (2026-06-17)
Verified building the cricket app foundation (Flutter 3.44.2, supabase_flutter 2.15, flutter_riverpod 3.3.2, go_router 17.3.0): (1) supabase_flutter 2.15 DEPRECATED `anonKey` in Supabase.initialize -> use `publishableKey` (the local `supabase status` prints an `sb_publishable_...` key). (2) riverpod_lint 3.x is wired via a top-level `plugins:` MAP block (`plugins:\n  riverpod_lint: ^3.1.4`), NOT a list and NOT `analyzer: plugins: custom_lint`; drop custom_lint. (3) `flutter_platform_widgets` is DISCONTINUED -> hand-roll adaptation with `Theme.of(context).platform == TargetPlatform.iOS` + `.adaptive()` ctors; one MaterialApp.router for both, Cupertino widgets render inside it. (4) Do NOT put CupertinoTabScaffold inside StatefulShellRoute (Flutter bugs #137833/#164300/#113757) -> use Scaffold + CupertinoTabBar on iOS, Scaffold + NavigationBar on Android. (5) For testable routing, switch the go_router redirect on an OVERRIDABLE provider (an AuthGate enum), not `client.auth.currentSession` directly, so widget tests override the gate value with no Session/SupabaseClient mock; also override the anon-bootstrap FutureProvider to a no-op so tests never touch the uninitialized Supabase.instance. (6) macOS iOS dev needs full Xcode.app from the App Store (CommandLineTools alone is insufficient; `flutter doctor` flags "Xcode installation is incomplete"); Android cmdline-tools install no-sudo via brew (openjdk@17 + android-commandlinetools + sdkmanager, needs platform/build-tools matching Flutter's required API level).

## Postgres: changing a function return type needs DROP, and table-returning fns break scalar contexts (2026-06-17)
`create or replace function` CANNOT change the return type - you must `drop function <full-sig>` then `create`. Dropping also forces PostgREST to reload the new shape. Also: a function declared `returns table(...)` is set-returning; calling it as a scalar sub-expression (e.g. `isnt(record_ball(...), null)`) throws "set-valued function called in context that cannot accept a set". Wrap it: `(select col from public.fn(...))`. Bare `select fn(...)` statements (side-effect only) are unaffected. Adding a NOT NULL column instantly breaks the inserting RPC and every caller, so ship column+RPC+test-updates as ONE atomic green commit, not separate ones.

## Workflow tool does not accept run_in_background (2026-06-17)
The `Workflow` tool is ALWAYS run in the background — you cannot (and must not) pass `run_in_background: true` like you can to `Bash` or `Agent`. Passing it returns `InputValidationError`. Just call `Workflow` without that field. You're notified when it completes; meanwhile, continue with foreground work.

## show_widget CSS variables silently break on dark theme (2026-06-17)
When using the visualize MCP `show_widget` to produce mockups, CSS variables `var(--color-background-primary)` and `var(--color-text-*)` resolve against the CLIENT's active theme. Utkarsh runs dark, so panels intended to look like "white phone on a sheet" rendered as dark-on-dark and the text disappeared. The read_me convention to "use CSS variables" applies to inert visualizations, NOT to mockup mode. Fix: lock mockup panel backgrounds and text to EXPLICIT light colors (white/dark text/cream cards/sand surface) and only keep brand accents (teal, amber) as explicit colors too. Future rule: any mockup widget = no theme variables for bg or text.

## User's GTM Avoidance Pattern (2026-05-28)
Utkarsh has technical operator's classic blocker: defaults to build work whenever GTM/sales/positioning gets uncomfortable. Evidence: 4+ sessions on Offer/ICP/GTM brainstorm, each one pivoted to a technical project (Aramas scraper, ScreenStudio, paperclip, n8n-reviewer) before reaching offer language. The "I don't have time" framing is a symptom, not the cause — the pattern is comfort-seeking, not scheduling.
Implication for future sessions: don't accept "I'll make time next week" as a plan. Push to structural change: (a) outsource the GTM work (positioning consultant, sales partner), (b) accept that GTM-self-doing isn't going to happen and route around it (multiply Yosef-style technical partnerships), or (c) force external commitments that can't be deflected (booked calls). The wrong move is to keep restarting the brainstorm — pattern wins unless structure changes.

**In-session scope-creep variant (observed 2026-05-28)**: After committing to Path 1 (multiply Yosefs via tech-leveraged scraper), user expanded same session to include faceless YouTube channel on contrarian AI + ComfyUI storyboard pipeline + automated posting infra. Naming it as a "different workstream" doesn't change the bandwidth math: parallel workstreams = neither ships. Action when this happens: name the pattern out loud, validate the new idea has merit, force capture-and-park into /Inbox or /Thinking, keep sprint scope hard-locked.

**STRENGTHENED to a core signal (2026-05-28)**: In ONE session, user gravitated to building a content/distribution engine THREE times: (1) prospect-scraper, (2) faceless YouTube channel [parked], (3) Twitter content engine sourcing research→AI→business-nuggets. Each pivot moved away from directly contacting prospects and toward building a system. This is not random scope-creep, it's a consistent preference: user is drawn to building distribution/content infrastructure, and resistant to direct outreach. Likely the real strategy is content-led inbound, NOT direct outreach. But content-led is a 3-6 month audience play and does not satisfy a "2 partners in 30 days" goal. Future sessions: when user proposes a content engine, force the explicit goal-timeline reconciliation (fast revenue vs long-game distribution) before speccing. Don't let both run in parallel.

**Teaching loop working (2026-05-28)**: Later same session, user began drifting to "newsletter" then caught it himself mid-sentence ("Again, this is what I swayed to"). The named pattern is now self-visible to the user in real time. Keep naming drifts plainly and without judgment — it's transferring. When user catches their own sway, affirm it matter-of-factly (not cheerleader-y) and move on. Resolution for both-pipelines tension: build sequentially (shared core → outbound → inbound), never parallel; the bandwidth cost is in BUILD not RUN.

## Writer-agent target = information architecture, NOT voice (2026-05-29)
Utkarsh's content writer-agent should produce a DENSE first-draft optimized for information density + architecture (validated facts, framing, interest build-up, reveal sequence), NOT voice/beautification. He does the final voice polish himself. This dissolves the long-standing tension with his writing-style-analysis.md rule ("don't templatize my voice, you're a probabilistic system"): the machine handles the templatable layer (structure/info), the human handles the un-templatable layer (voice). When building any drafting tool for him, aim the machine at structure + density, leave voice to him, and treat the agent's output as a scaffold-to-react-to, not a finished piece. Voice samples (2 real posts) live in Projects/content-engine/voice-samples.md; thinking process in writing-style-analysis.md.

## Content engine validated by live run, not by spec (2026-05-29)
For a reasoning-heavy system (the content engine = Claude reasoning + dynamic research + curation), the fastest proof is to RUN it live before building any infrastructure. A single opus sub-agent, given the stage-playbook + 4 reference files + a real source, produced mechanism-grade nuggets, dynamically-researched supporting/contrarian evidence, distinct angles, a dense on-voice draft, a programmatic graphic_spec, and an honest self-critique, all with zero code. Lesson: when the value is in reasoning/judgment, demo it end-to-end early; the "build" (scraper, graphics lib, Kanban) is just plumbing around a reasoning core you can validate immediately. The sub-agent pattern (load reference files as context, run the pipeline, return cards + self-critique) is the engine's actual runtime in approach A.

## Scraper build insights (2026-05-29)
- **WeWorkRemotely content-negotiates on Accept header**: default request (no Accept) returns an RSS/XML feed; `Accept: text/html` returns server-rendered HTML (~106 jobs, ~225KB). A generic get_text without the header = silent 0-jobs bug. WWR selectors: `li.new-listing-container` (entry), `span.new-listing__header__title__text` (title), `p.new-listing__company-name` (company), `a.listing-link--unlocked` (job link, relative href). Sponsored `li.listing-ad` entries lack a title so skip naturally.
- **Verify SOURCE ICP-yield, not just scraper correctness**: WWR's programming category + Utkarsh's narrow ICP keywords yielded 0 (broad "engineer" = 32). General job boards list companies hiring devs, not necessarily AGENCIES hiring automation partners (the actual ICP). Technical green tests do not mean a source surfaces fit prospects. The higher-yield sources for "agencies with delivery overflow" are likely Indeed with agency-targeted queries + the probing/qualification layers, not more general dev boards. Reconsider source priority accordingly.

## Supabase + pgTAP backend gotchas (2026-06-15, cricket app)
Building a Supabase backend locally with pgTAP TDD surfaced three reusable gotchas (all cost a red-loop):
- **Local `supabase db reset` does NOT auto-grant DML to `authenticated`.** Prod grants via default privileges; local does not. With RLS on + no table grant, `authenticated` gets `permission denied for table X` (not an RLS row filter). Fix: every table needs `grant select, insert, update[, delete] on <table> to authenticated;` in its migration. Tables written through SECURITY DEFINER RPCs only need `select` granted (writes bypass RLS as owner).
- **psql does NOT interpolate `:'var'` inside `$$..$$` dollar-quoted strings** (sends `:'var'` literally -> `42601 syntax error at or near ":"`). Inside `throws_ok`/`lives_ok` SQL-string args, identify rows with a subquery, not a `\gset` var. `:'var'` works fine in bare SQL (`is()`/`isnt()` args).
- **LANGUAGE sql function bodies are validated at CREATE time** (check_function_bodies=on), so a sql helper that references a table must be migrated AFTER that table. plpgsql bodies are NOT validated at create, so they tolerate forward references (resolved at first call). Order migrations accordingly.
- **Test helpers belong in `seed.sql`, not `tests/`**: each `tests/*.sql` runs in its own rolled-back transaction, so an install there does not persist. Vendor basejump `supabase_test_helpers--0.0.6.sql` into seed.sql (strip the leading `\quit` psql guard line); the in-database dbdev client is deprecated. seed.sql is local-only (not applied by `db push`).
Tooling: user's Mac runs OrbStack (not Docker Desktop) for containers; `open -a OrbStack` to start the daemon. Supabase CLI installed via brew.

More gotchas from the Scoring Core build (2026-06-16):
- **Shifting a monotonic seq up by 1 collides on a non-deferred unique index.** `update set seq = seq+1 where seq > N` fails with a duplicate-key error (row-by-row check; seq3->4 hits the existing seq4). Fix: two-step negation - `update set seq = -(seq+1) where seq > N; update set seq = -seq where seq < 0;` (negatives never collide with positives). Or make the unique a DEFERRABLE constraint.
- **Event-sourced fold that derives strike makes stored striker columns cosmetic.** Because `compute_innings_state` re-derives the striker every call from the opening pair + ordered deliveries, an `edit_ball`/`delete_ball` needs NO re-stamping of later rows - the fold handles the whole cascade. Stored striker_id is just a "what we thought at insert" convenience the fold ignores. This is what makes full-correction cheap.
- **pgTAP `is()` is strictly typed:** `sum(...)` returns bigint; comparing to an int literal raises "function is(bigint, integer, unknown) does not exist". Cast the aggregate to `::int` (or the literal to bigint).
- **Build the fold as one PL/pgSQL function grown by `create or replace` across TDD increments** (totals -> strike -> extras -> ... -> result). Each increment = one failing pgTAP test + the minimal logic; the function is the single rule-home. Worked cleanly for a ~250-line cricket engine, 145+ assertions.

## Git/SSH on this Mac (2026-05-28)
Port 22 is BLOCKED on the user's network (SSH-over-22 times out, HTTPS-443 works). GitHub SSH must go over port 443: `~/.ssh/config` has `Host github.com / Hostname ssh.github.com / Port 443 / User git`. Auth key = ed25519 at `~/.ssh/id_ed25519`. Remote = `git@github.com:utcursh-creator/pinto`. HTTPS password auth is dead (GitHub disabled it). git author identity is still auto-derived (utkarsh@utkarshs-MacBook-Pro-2.local) — user hasn't set global user.name/user.email. If pushes fail with timeout, it's the port-22 thing; the 443 config fixes it.

## Apify Actors for Scraping (researched 2026-05-28)
For job-board scraping, Apify pre-built actors offload anti-bot + maintenance. Free plan = ~$5/mo platform credits; pay-per-result charged against it (low volume = effectively free).
- **Indeed (incl. indeed.de)**: `borderline/indeed-scraper` is the pick ($5/1k, no login, DE support, 4.8/5, returns company website/industry/size). `misceres` is Apify-maintained but 3.3/5 + no documented non-US domains.
- **LinkedIn**: no-cookie actors (`get-leads/linkedin-scraper`, `harvestapi`) DO work in 2025-2026 via public endpoints, no account/ban risk, free-viable ($1-3/1k), BUT flaky (~3.3/5) and public-data-only. Cookie-based actors (`curious_coder`, 4.9/5) are rich+reliable but need YOUR session cookie (ban risk) + $30/mo rental. Rule: use no-cookie as a flaky bonus, never a hard dependency; validate each run.
- Apify actors typically DON'T return contact emails (still need separate enrichment), but DO return company website → can skip the company-resolution step.
- Reusable distinction: LinkedIn-as-data-source (scraping public data, fine) vs LinkedIn-as-channel (posting/outreach, which this user rejects). Different things.

## Positioning vs Channel Tension (2026-05-28)
User's positioning is high-tier (Forward Deployed AI Partner, peer not vendor). Templated cold-outreach in response to a job post is STRUCTURALLY vendor-tier no matter how the words are written. The medium codes the message before the words do. When proposing outreach for high-positioning operators, do not auto-default to job-post-response templates. Either: (a) accept the positioning compromise explicitly, (b) change the channel to peer-to-peer (slower), or (c) decouple the prospecting signal from the outreach narrative (use job post as intel only, email never references it). Surface this trade-off, don't paper over it.

## Tokio Reactor Requirement Is Broader Than Just spawn (2026-04-18)
Not only `tokio::spawn` requires a runtime — **any tokio I/O type conversion** that registers with the reactor also panics from non-runtime threads. Specifically:
- `tokio::net::TcpListener::from_std(std_listener)` — registers the socket with the I/O driver
- `tokio::net::TcpStream::from_std(std_stream)` — same
- `tokio::fs::File::from_std(std_file)` — same
- `tokio::signal::unix::signal(...)` — same

Symptom is identical: `there is no reactor running, must be called from the context of a Tokio 1.x runtime`. When debugging, check every tokio API call in the panic's file, not just `spawn`. Fix: move the conversion INSIDE an async task (via `tauri::async_runtime::spawn`) where runtime context is guaranteed.

## Tauri v2 Sync Commands Can't Call tokio::spawn (2026-04-18)
Tauri v2 dispatches synchronous `#[tauri::command]` functions on a blocking thread pool WITHOUT binding the tokio runtime handle to that thread. Calling `tokio::spawn(...)` from inside a sync command panics with: `there is no reactor running, must be called from the context of a Tokio 1.x runtime`. Two fixes:
- **Preferred**: use `tauri::async_runtime::spawn` instead — Tauri's wrapper uses its managed runtime and works from any thread context. Returns `tauri::async_runtime::JoinHandle<T>` which has `.abort()` and can be awaited like tokio's.
- **Alternative**: make the command `async fn` — then Tauri runs it on the async runtime and `tokio::spawn` works inside the call chain.
The error is silent in release builds (GUI subsystem = no stderr), so this class of bug hides until you have file-based logging.

## Tauri v2 Windows GUI Subsystem Has No Console (2026-04-18)
Release builds for Tauri v2 on Windows link with the GUI subsystem (`windows_subsystem = "windows"`), which means stdout/stderr are NOT attached to a parent terminal. `eprintln!` and `println!` output is discarded. When debugging a GUI app crash:
1. Don't rely on terminal output — write to a log file at `%LOCALAPPDATA%\<AppName>\debug.log` instead
2. Install `std::panic::set_hook` early in `run()` — writes panic payload + `std::backtrace::Backtrace::capture()` to the file
3. Wrap background threads in `std::panic::catch_unwind` so panics don't silently abort threads
4. For async tasks, use `futures_util::FutureExt::catch_unwind(AssertUnwindSafe(future))`
5. Use a `dlog!` macro so callers don't have to manually pass a file handle

Alternative: call `AllocConsole()` from Win32 to attach a console at runtime — more invasive.


## Tauri v2 Multi-Word Command Args (2026-04-17)
Tauri v2 auto-converts Rust `snake_case` command arg names to `camelCase` at the IPC boundary by default. A command `fn foo(mic_id: String)` expects JS to send `{ micId: ... }`, NOT `{ mic_id: ... }`. Single-word args (`target`, `state`) are unaffected since conversion is a no-op. Symptom: `invalid args 'micId' for command 'foo': missing required key micId`. Fix: `#[tauri::command(rename_all = "snake_case")]` on the command. Check every command with multi-word args (mic_id, frame_index, project_path, file_path, etc.) when adding new IPC.


## Tauri v2 Title Bar Buttons Not Working (2026-04-16, TRIPLE-CORRECTED)
**Symptom**: min/max/close buttons render but do nothing when clicked.
**Wrong diagnoses (wasted 3 attempts)**: assumed drag-region interception — tried splitting `data-tauri-drag-region`, then adding `-webkit-app-region: no-drag`. Neither was the issue.
**Actual root cause**: Tauri v2 permissions system. `capabilities/default.json` had only `core:default` which does NOT include window operation permissions. `getCurrentWindow().minimize()` IPC call was silently rejected (no `.catch()` on the returned promise → swallowed error). Fix: add explicit permissions `core:window:allow-minimize`, `allow-toggle-maximize`, `allow-close`, `allow-start-dragging`, `allow-set-focus`, `allow-show`.
**Lesson**: When Tauri IPC calls fail silently, check capabilities/permissions FIRST before debugging UI/DOM issues. Tauri v2's permission model is strict — every webview → Rust IPC call needs explicit permission in capabilities JSON. `core:default` is minimal and does NOT include window operations.

## User Preferences Noted (2026-04-15)
Prefers subagents use `opus` (4.6 with extended thinking) for non-trivial tasks — use sonnet/haiku only for purely mechanical work. Surface this when choosing models.

## Subagent-Driven Development Lessons (2026-04-15)
- Writing config that calls into itself recursively is a class of bug that mechanical review passes miss. `beforeBuildCommand: "pnpm build"` + `"build": "tauri build"` → infinite loop. `check:all` passed green because it doesn't run `tauri build`. Always trace what every npm script ACTUALLY INVOKES before shipping.
- Hand-rolled TypeScript ambient decls (.d.ts shims) will drift from the real library API. Include the full option surface or don't bother — a subtly wrong decl is worse than no decl (it lies to callers).
- Generic type boundaries like `invoke<K extends keyof EmptyMap>()` collapse to `never` when the map is empty, making the function uncallable-but-looks-typed. For a boundary that starts empty, either add a placeholder sentinel or don't ship the generics until the first real entry.
- Tauri's `capabilities/default.json` `:default` permissions are broad. Scope per-feature or the installer ships with shell.open + fs.read across a wide allowlist — security debt.
- Cargo `"2.0"` is caret-semver (`>=2.0, <3.0`). For pinning intent use `"=2.0.x"` or tilde `"~2.0"`. Otherwise commit Cargo.lock (for binary crates you should anyway).
- Vitest tests that only assert `getByText(...)` exists are cosmetic. If the handler surface (button clicks, keyboard shortcuts, router transitions) isn't exercised, check:all is green-but-meaningless.
- When a config change (like aliasing `build` to `tauri build`) crosses multiple files, ALWAYS trace the call graph both directions, not just forward.

## Screen Studio Clone — Core Architectural Insights (2026-04-15)
- For SS-style apps: the raw recording is NEVER baked. Compositor re-renders every frame from a JSON project config (non-destructive edits, preview = exporter on live frame).
- Auto-zoom is NOT AI. Deterministic pipeline: click-event clustering (bounded by zoomed-viewport size) → spring-smoothed focal point → edge-snap remap. Cap.so: `crates/rendering/src/zoom_focus_interpolation.rs`.
- Cursor smoothing = analytic spring-mass-damper per axis (frame-rate independent). NOT moving avg, NOT Kalman, NOT Catmull-Rom. Cap.so: `spring_mass_damper.rs`.
- WebView2 does not expose `ImportExternalTexture` for D3D11 shared handles — preview transport must be localhost WebSocket with raw RGBA/NV12 binary frames. Tauri IPC is too slow for per-frame payload.
- Win11 glass: `window-vibrancy` crate → `apply_mica` (main window) + `apply_acrylic` (popovers). Win10 fallback via `SetWindowCompositionAttribute`.
- Best open-source reference for any SS-style project: CapSoftware/Cap (Tauri v2 + Rust + SolidJS + wgpu + ffmpeg-next + windows-capture + cpal + nokhwa).

## Writer Agent Voice Debt (2026-04-15)
- Reading a voice library in a prompt is not the same as embodying it. The Writer agent's AGENTS.md points to voice-library.md as required reading but the Writer still produced 4 reworks that all followed `[observation] - [reframe to delivery/capacity thesis]`. Descriptive instructions ("be him", "sound like a practitioner") don't override the LLM's default "insight comment" template.
- Fix will need to be mechanical: inject specific sentence starters, rhythm patterns, banned structural shapes, and first-word variety enforcement directly into the Writer prompt. Not more "be Anand" prose.
- Also: the deployment-gap thesis is an attractor for this Writer. Every unconstrained output pulls back to it. Treat this like a bias-correction problem.

## Progress > Polish When Flow Is Partial (2026-04-15)
- User called Writer optimization "a necessary distraction" and chose to park it in a still-broken state to complete end-to-end flow test (Apollo Task 22). Signal: getting the whole pipe working once is more valuable than any single component being perfect.
- How to apply: when a sub-optimization is blocking flow progress and the overall system has never run end-to-end, bias toward parking the sub-optimization with a clean TODO and pushing through to the full flow test first.

## Paperclip API: X-Paperclip-Run-Id Semantics (2026-04-10)
- The `X-Paperclip-Run-Id` header is a heartbeat run identifier, not an arbitrary idempotency token. Value must be a UUID AND must already exist in the `heartbeat_runs` table (FK constraint `activity_log_run_id_heartbeat_runs_id_fk`).
- If you're calling from outside an agent heartbeat (e.g., board user, manual API call, orchestration script), OMIT the header entirely. Server will skip the activity log write.
- This came up twice — both times I reached for a synthetic ID. Don't repeat.

## Diagnosing Confused Codebases (2026-04-15)
- When a codebase "feels confused," read the Prisma schema / data model FIRST — it reveals original intent better than the marketing framing does.
- n8n-workflow-reviewer example: it was being called "version control" but the schema has `reviewToken`, `authorRole`, `ChangeSelection`, `approved/changes_requested/merged/pushed` statuses. That's a Pull Request data model, not a VCS data model. The data doesn't lie; the framing did.
- When presenting diagnosis, lead with what the code IS, not what it was called. Then offer 2-3 coherent paths forward. Utkarsh responds to concrete choices, not open-ended "what should we do."

## Prisma + Supabase Migration Gotcha (2026-04-15)
- `npx prisma migrate dev` failing with "FATAL: Tenant or user not found" almost always means either (a) Supabase project is paused (free tier auto-pauses after ~1 week idle — restore via dashboard.supabase.com) or (b) DB password rotated and `.env.local` has stale DATABASE_URL / DIRECT_URL.
- Not a code issue. Not a Prisma config issue. Check project state first before debugging the migration.
- Applies broadly to any Supabase-backed Prisma app in the user's portfolio (n8n-workflow-reviewer, vibelife-scraper, etc).

## Don't Unilaterally Strip Half-Built Work (2026-04-15)
- User pushback: "why are we removing half built layers instead of finishing them up? won't those be included in the scope?"
- Why: Don't optimize for shipping speed by discarding in-progress work without explicit user approval. Finishing > stripping by default.
- How to apply: When a codebase has half-built features, propose FINISHING them as the default. Only suggest stripping if (a) the feature has no identifiable purpose AND (b) you've asked the user to confirm. Removing genuinely dead code with no purpose is "finishing it" with the honest answer — different from abandoning working features.

## Composing VC + PR Without Fighting n8n (2026-04-15)
- "Version control for n8n" as a standalone pitch is dead (n8n shipped autosave + rollback Jan 2026, free all tiers).
- BUT: "reviewed change history" = PR + versioning composes cleanly AND is defensible. Every approved PR is a commit; the timeline is the history. n8n will never ship the review layer, so the audit-trail framing is durable.
- Diff the two pitches for clarity: n8n's versions are keystroke-level, anonymous, noisy; a reviewed-history tool stores only approved versions with author, approver, comments, semantic diff, permanent retention, named tags, and revert-via-reverse-PR.
- Framing shift: stop saying "version control" — say "reviewed change history" or "audit trail for approved changes."

## Agency-Operator Pain Reality Check (2026-04-15)
- Do NOT assume agency operators / AI solution sellers care about problems that sound technically interesting. They avoid most ops problems via process (hands-off agreements, one-instance-per-client, hard handovers) rather than tooling.
- Before claiming something is "hair-on-fire pain," test: does the ICP currently pay money to avoid it, or do they just live with it via convention?
- My "concurrent editing / 3-way merge" framing failed this test for agencies — it's solo-dev pain or Utkarsh-specific pain (Yosef setup), not generalized agency pain.

## System Learnings
- Utkarsh's communication style is context-dependent — match his energy. Concise for direct info, detailed when reasoning is needed.
- He thinks in processes and bottlenecks. Frame suggestions that way.
- His positioning doc (.claude/context/memory/CLAUDE.md) contains his complete worldview, thinking patterns, and business model. Reference it when creating content.

## How to Assist Him (Meta-Learnings)

### Don't Be Deterministic
- He called out: "you just read my md files and picked the closest thing to it — that's being deterministic, you're a probabilistic system."
- Don't read notes about him and replay the closest pattern. Understand the MECHANISM of his thinking.
- His latent space ≠ what's written in files about him. The files are snapshots. His thinking is a living process that connects things in new ways each time.
- When approaching content ideas: explore the possibility space, don't template from prior outputs.

### Go to Primary Sources
- When he says "what did a16z say?" — he means go read the actual article, not your summary.
- Always work from primary sources (the actual report, article, data) not from summaries or abstractions.
- The thinking should start FROM the source material, not from your notes about it.

### Understand Before Proposing
- Do proper research BEFORE proposing content ideas. Deploy sub-agents for deep research.
- Don't propose 5 ideas that are all the same thesis in different clothing. He caught: all 5 ideas orbited "deployment gap" when he'd already published on that.
- Map the audience's understanding capability FIRST before proposing content.
- Track what he's already published so you don't repeat the same topical territory.

## Workflow Learnings

### Paperclip API (2026-04-10)
- `X-Paperclip-Run-Id` header requires a UUID that EXISTS in the `heartbeat_runs` table (FK constraint `activity_log_run_id_heartbeat_runs_id_fk`). When calling API from outside an agent heartbeat (e.g. board/manual), omit the header entirely.
- Writer agent completes one task per heartbeat wake cycle. To process N tasks, may need N wakeups or let heartbeat timer handle it.
- Writer self-blocking on VIB-30 (Dutch emails) was correct behavior — flagged limitation honestly rather than producing bad output.

### Writer Agent Voice Quality (2026-04-10)
- Writer's AGENTS.md has good directional instructions ("be him", "text to Yosef test") but lacks concrete mechanical grounding from the voice library. Result: all outputs converge to same `[observation] - [delivery thesis reframe]` pattern.
- The "deployment gap" thesis is the Writer's gravitational attractor. Every comment lands on delivery/capacity/bottleneck. Utkarsh explicitly flagged this as robotic.
- Fix needed: embed specific voice patterns (sentence starters, rhythm, thought-breaking patterns, actual word choices) from voice-library.md directly into AGENTS.md so the Writer has mechanical anchors, not just aspirational descriptions.

## Content Learnings

### Content Creation Rules (from direct corrections)
- His worldview is the LENS, not the SUBJECT. Content is about the audience's problems, seen through his perspective.
- Never frame content like a reporter/news channel. He is a practitioner, not a commentator.
- Research papers are EVIDENCE cited within a practitioner's perspective — not topics to report on.
- Don't repackage his positioning back to him. Absorb it, then BUILD on it with new research and concrete data.
- Dumb everything down — "girlfriend's uncle" level. Nobody searches for or understands high-level abstractions.
- "High-level agency" positioning energy — authoritative but simple, never preachy.
- Don't use marketing frameworks explicitly in content (no "awareness/nurture/convert" language in the actual posts).
- 1:1:1 framework = 1 Awareness + 1 Nurture + 1 Convert post, 3x/week.
- Two audience segments: A (business owners hitting walls with no-code/AI) and B (agency operators needing fulfillment).
- The rehook/opening must relate to the problem that's going to be discussed or framed in the post.
- Don't propose ideas that all orbit the same thesis. Diversify topical focus.
- Track what's already published — never repeat the same angle he's already posted.

### Thinking-to-Content Process
See full analysis: `Projects/content-engine/writing-style-analysis.md`
- The file maps his COGNITIVE PROCESS, not surface writing patterns. Do NOT mimic sentence structures or phrases across posts.
- Pipeline: Absorb research → Map the system behind the data → Find the non-obvious connection → Earn the insight through buildup → Land on value for the reader.
- Each post should feel structurally DIFFERENT. The framing adapts to what the idea needs, not a template.
- His thinking = systems thinking. He connects separate data points into one story that reveals a gap.
- The insight is EARNED through evidence, never stated upfront. Reader should arrive at "I see it now" not "he told me something."
- NEVER repeat the same hook/structure/format across posts. Predictability kills curiosity.
- The LinkedIn posts are NOT a template to copy. They show how his mind works. The phrases, sentence structures are what happened to come out for THOSE specific ideas. Next time needs different entry, pacing, structure.

### Published Content (Don't Repeat These Angles)
- **LinkedIn article**: "AI Business Outlook for 2026" — PwC CEO survey, circular AI spending (Nvidia→OpenAI→Oracle), 56% zero returns, McKinsey winners redesigning workflows, adoption gap as opportunity
- **LinkedIn post**: Claude Skills — domain experts can monetize by packaging expertise into AI skills
- **Ben's community post**: Technology works, deployment is broken, gap is the opportunity
- All three cover variants of "deployment/adoption gap." He explicitly said: "it seems this is all I talk about." New content must explore DIFFERENT topical territory.

## Technical Learnings

### Bright Data Scraping Browser + Playwright cookie injection (2026-04-09)
- **`browser.contexts[0]` is a persistent context, not ephemeral.** Bright Data's Scraping Browser keeps cookies in the default context across CDP reconnects. Don't assume it's empty.
- **Chromium 146+ `Storage.setCookies` rejects overrides.** Throws `Protocol error (Storage.setCookies): Overriding [cookie names] is forbidden`. This is a Chromium-side guard, not a Bright Data block per se.
- **`context.clear_cookies()` does NOT reliably clear the jar in Bright Data Scraping Browser.** The CDP call returns success but `setCookies` still sees the same cookies as existing. Likely no-op'd or routed to a different store than `setCookies` checks.
- **`browser.new_context()` does NOT help** — Bright Data shares a single global cookie store across all contexts (default + new). `new_context()` succeeds but `add_cookies()` still hits the same guard.
- **Raw CDP `Network.setCookie` ALSO blocked** — same "Overriding ... is forbidden" error. Bright Data intercepts ALL cookie mutation at the CDP proxy level, not just Playwright's high-level API. Their unblocker manages cookies exclusively and prevents any client-side writes.
- **`Network.deleteCookies` ALSO blocked** — same "Overriding" error. Bright Data locks the entire cookie store: no create, no update, no delete via any CDP method. Cookie injection is architecturally impossible on Bright Data Scraping Browser.
- **Only viable path for authenticated scraping via Bright Data**: use their built-in login flow (navigate to login page, `page.fill()` credentials, let unblocker handle CAPTCHAs). Cannot use cookie injection.
- **Bright Data enforces robots.txt by default** — `Page.navigate` throws `(brob)` error if target URL is blocked by site's robots.txt. Must disable robots.txt enforcement in the zone settings in the Bright Data dashboard (or request full access from account manager).
- **Patchright is the 2026 answer to Akamai for Python scrapers** — `patchright` on PyPI (1,299 stars, maintained as of 2026-04-10). Drop-in Playwright replacement, patches CDP at binary level. `playwright-stealth` only patches JS-level tells which Akamai ignores (TLS fingerprinting is their primary detection). `rebrowser-playwright` is Node.js only — no Python port.
- **Railway pricing is usage-based since 2024** — no more fixed $5 "Hobby Plan". A Playwright container (~700MB RAM) costs $12-18/mo always-on. For memory-hungry long-running scrapers, Hetzner CX22 (€4.51/mo, 4GB RAM) is the clear winner.
- **`claude-3-haiku` is deprecated by mid-2026** — use `anthropic/claude-haiku-4-5`. Pricing: ~$0.80/M input, $4.00/M output (up from $0.25/$1.25). Still cheap enough for 3000 evals/month (~$4.32/mo).
- **PyPI package name gotcha: `2captcha-python`** (official) vs `twocaptcha-python` (unofficial alias). Use the official one. Also `pydantic-settings` is a separate package from `pydantic` since v2.
- **Chromium `net::ERR_PROXY_AUTH_UNSUPPORTED` is actually a 407 in disguise** — when proxy auth fails, modern Chromium reports it as this unhelpful error. Always isolate via httpx first: `httpx.get(url, proxy='http://user:pass@host:port')` to confirm whether credentials are valid before blaming the browser.
- **IPRoyal country-targeting requires plan support** - appending `_country-de` to username only works if the account has country/geo modifiers enabled. Some plans route randomly (returns US/EU IPs on rotation) even when bare auth succeeds. Test format in dashboard's "auth string builder" before coding.
- **IPRoyal modifiers go on PASSWORD, not username** - format is `user:pass_country-de_session-XXX_lifetime-10m`. Username stays bare. User is `EOTzQbgFunmwODqB`, composed pass is `7BJ9TzpjG9BZj54l_country-de_session-abc_lifetime-10m`. All the `user_country-de` variants return 407 because IPRoyal parses modifiers from the password field.
- **StepStone recruiter portal**: Login URL is `https://www.stepstone.de/5/recruiterspace/login` (the old `/5/index.cfm?event=login` returns 403 "Error - Access denied"). Unauthed navigation to DirectSearch auto-redirects here. Form uses `input[name='username']` (not `email`/`login`), `input[name='password']`, submit button text "Anmelden".
- **StepStone deferred cookie banner**: `#GDPRConsentManagerContainer` with `.cc-accordion` children loads asynchronously after initial page render - misses your initial banner dismissal. Blocks submit click with "subtree intercepts pointer events". Hide via JS before submit: `document.querySelectorAll('#GDPRConsentManagerContainer, .cc-accordion').forEach(el => el.style.display = 'none')`.
- **Login success check pattern**: don't test URL-contains-"login" because post-login URLs on many sites still contain "login" as query fragment/redirect param. Check for absence of the login form inputs instead: `has_username_input || has_password_input`.
- **StepStone DirectSearch structure** (live 2026-04-17): combined search field `#searchfield__textfield` with placeholder "Geben Sie Jobtitel, Ort oder Fachkenntnis ein" - just type "job_title location" and press Enter. No separate location/radius UI by default. Results in `.miniprofile` cards (10 per page, configurable 10|25|50). Profile ID from `a.miniprofile__name[href*='profileID=XXX']`. Clicking that link unlocks and opens `div.ngdialog:last-of-type` with full contact data. CV download via `a[href*='downloadAttachment']` (available both in preview card and dialog).
- **Regex extraction beats CSS selectors for structured dialog text** - when content has stable labels ("Email", "Mobil", "Wohnadresse", "StepStone ID") followed by values, regex patterns are more resilient than chasing CSS classes that change with framework updates.
- **Bot-detection bypass via live testing** - when a proxy-masked user agent (Patchright + IPRoyal DE) successfully loads StepStone recruiter pages AND submits logins AND scrapes DirectSearch results without any visible CAPTCHA or block, the stealth stack is working. Akamai's `_abck` cookies are set normally and session persists.
- **Recruitee offer stages are inline, not separate** - `GET /c/{company}/offers/{id}` returns the full pipeline in `offer.pipeline_template.stages[]`. Do NOT query `/pipeline_templates/{id}` (returns 404) or `/offers/{id}/pipeline` (404) or `/offers/{id}/stages` (404). Stages have `id`, `name`, `position`, `group` ('applicants'|'active'|'hires'), `category` ('referred'|'sourced'|'apply'|'phone_screen'|'evaluation'|'hire'|'none'). Match by case-insensitive name.
- **Pydantic alias for backward-compat fields** - when n8n/external clients send `title` but your model uses `job_title`, use `Field(validation_alias=AliasChoices("job_title", "title"))` with `populate_by_name=True` to accept both. Combine with `extra="ignore"` in model_config to tolerate extra fields like `account`/`credits_remaining` without breaking validation.
- **Claude Haiku 4.5 wraps JSON output in markdown fences** - `anthropic/claude-haiku-4-5` returns ` ```json ... ``` ` even when the prompt says "Respond in JSON format only, no other text". The older `claude-3-haiku` and `claude-3.5-haiku` don't do this. If your parser does `json.loads(content)` directly it silently fails. Always strip fences: regex `^\s*```(?:json)?\s*(.*?)\s*```\s*$` with `re.DOTALL`, or fall back to first-`{` last-`}` slicing.
- **Lock-before-webhook ordering in chain-dispatch patterns** - if service A holds a concurrency lock while sending a webhook to service B, and B immediately fires a chain-dispatch back to A, A gets a 409. Fix: release the lock first, then send the webhook. The webhook doesn't need the browser/scraper state - it's just an HTTP POST with already-collected results. Pattern: `result = await do_work()` inside lock, then `async with lock: ...` exits, then `await send_webhook(result)` outside lock.
- **Silent exception handling in webhooks is a bug magnet** - `except (HTTPStatusError, TimeoutException): return False` will swallow any other error (ConnectError, ReadError, RemoteProtocolError, PoolTimeout, unhandled 5xx). Always log before returning failure, include payload size + HTTP status code. For webhooks that carry base64-encoded files, timeouts need 60-120s, not the httpx default 5s or the commonly-copied 30s.
- **PowerShell `Get-Clipboard | Out-File` gotcha**: if the user's clipboard wasn't actually replaced with the JSON before they ran the command, the file ends up containing the literal command itself. Always validate file contents (not just existence) before proceeding.
- **StepStone DirectSearch JWT structure**: `PHRECRUITERAUTHCOOKIE` = main session JWT (~24h validity); `authHash` = short-lived authorization JWT (refreshes server-side from session cookie on each request); `authHash.permissions` array contains entitlement flags like `PRODUCTS_DIRECT_SEARCH` — useful for confirming account access at the cookie level without hitting the UI.

### Vibelife Website (2026-04-02)
- **GSAP ScrollTrigger + opacity bug**: `gsap.from()` with ScrollTrigger sets initial state to `opacity: 0`. If the section is already in viewport on load (or with Lenis smooth scroll), the trigger never fires and elements stay invisible. Fix: use `FadeInView` component instead of raw GSAP for scroll-triggered animations.
- **Brand system on text emphasis**: BRAND-SYSTEM.md explicitly says highlighted text = gold background with dark text OR solid `text-gold`. Never multicolor gradient text (`bg-gradient-to-r from-gold via-teal to-gold bg-clip-text text-transparent`). This looks generic/corporate.
- **PDF reading on Windows**: Use pypdf (pdftoppm not available).

## Copywriting Learnings (2026-04-02)

### Principles Applied
- **Ogilvy**: Headline does 80% of the work. Don't be clever — be clear.
- **Hopkins**: Specificity creates believability. "5 projects in 21 days" > "we handle fulfillment."
- **Schwartz**: Enter the conversation already in the buyer's head. Don't create desire — channel existing desire. Match the market's awareness level.
- **Halbert**: Lead with their reality, not your offer.
- **Hormozi**: Offer = dream outcome × perceived likelihood / (time delay × effort).

### Copy Mistakes Caught
- "You Sell AI Automations. We Build Them." — descriptive, not persuasive. Describes service from seller's POV instead of entering buyer's conversation.
- "What would you sell this month..." — assumes buyer's strength is sales. Many are strategists, experimenters, relationship-builders. Don't narrow.
- Perspective disconnect: proof line (3rd person, "one business") → identity line (2nd person, "you didn't start...") felt jarring. Headline + subtext must flow as ONE thought.
- Don't show pricing or internal GTM terminology (bridge project, rev-share) on landing page. Present as "what we provide + what you get."
- Proof-first headlines stop scrolls better than identity statements for this audience.

## 2026-07-06 - Full-sweep session
- **Cupertino snackbars were dead app-wide**: `CupertinoPageScaffold` provides no `Scaffold`, so `ScaffoldMessenger.showSnackBar` had nowhere to render on iOS - every toast was silently invisible. Fix: AdaptiveScaffold embeds a `Scaffold(backgroundColor: transparent)` inside the CupertinoPageScaffold (also supplies the Material ancestor). Widget tests on Android masked this for months; the iOS-platform test caught it.
- **The device gate catches what mocked widget tests cannot**: matchSquadProvider selected `is_keeper` but the real column is `is_wicket_keeper` (the RPC PARAM is `_is_keeper` - param and column names differ!). 183 widget tests passed because they override the provider; the sim run failed in seconds with 42703. Never claim a select-string change verified without a live round-trip.
- **Retirements/strike swaps as EVENT ROWS in the deliveries stream** (fold v14): `event_kind` enum + nullable bowler + `is_legal` REDEFINED as "counts as a legal delivery" keeps every modulo/count consumer correct with zero special-casing. Event rows discriminate on `bowler_id is null` style constraints; old data unaffected because event_kind is null there. Lockstep rule held: state fold + cards fold + restamp all updated together.
- **Adding a default cap can break history**: enforcing ceil(overs/5) bowler quota by default would have failed dozens of legacy fold tests (they alternate 2 bowlers over long innings). Enforce from `rules.max_overs_per_bowler` only, and have the APP stamp the rule into new matches - old data stays valid, real matches get the rule.
- **start_innings server validation must be conditional on BOTH squads being declared** - stats fixtures legitimately declare one-sided partial squads; hard validation would break them. The wizard path always declares both, so the check bites exactly where it should.

## Auditing your own work (2026-07-07, the penetration review)
- **Run any adversarial audit TWICE and merge.** Two identical 12-front runs produced 83 and 87 confirmed findings; only 74 overlapped. 20 real defects would have been missed by trusting a single run. Verifier agents are non-deterministic - the second pass is cheap insurance, not redundancy.
- **Add a COMPLETENESS CRITIC after the fronts.** Give it the list of confirmed findings and ask "what did all of these miss?" It found a CRITICAL that all 12 specialised fronts missed, because it lived in the SEAM between two subsystems (a tournament RPC's consent gate blocking a UI action that a different subsystem's default made mandatory). No single-front reviewer owns a seam.
- **Make the skeptic default to REFUTED.** Pairing each finder with an agent told to refute-or-confirm against real code, correcting severity, is what makes the output actionable instead of a pile of maybes. Several skeptics also narrowed scope correctly (e.g. "the follow-on delete only works for members with no squad history").
- **RUN the test suites yourself; static review will not.** `flutter analyze`/`flutter test` were clean, but `supabase test db` FAILED - a fact no reading agent produced. Empirical runs are a separate evidence class from code review; do both.
- **A green test suite can be a lie in a specific way: vacuous guard tests.** 13 pgTAP files addressed rows via unscoped `(select id from public.matches limit 1)` instead of the id they had already `\gset`. On a one-row DB it passes by accident; with any other data it hits a DIFFERENT row and throws a DIFFERENT error - and `throws_ok` matching only the errcode class (P0001) still passes. The constraint under test is never exercised. **Always scope test fixtures to ids the test itself created, and assert on the message, not just the code.**
- **"Lockstep" invariants need a TEST, not a comment.** I wrote "LOCKSTEP RULE" in the fold v14 migration header and still shipped three folds that disagree on squad_size, because nothing asserted state == cards == restamp. An invariant with no executable check is a wish.
- **When you refactor a function by copying its body, you inherit its bugs verbatim.** fold v14 was copied from v13; the hardcoded `squad_size=11` in cards/restamp came along untouched while state had already been fixed. Diff the copies against each other, not just against the intent.
- **A deferral note in a migration is a future bug.** `add_tournament_team`'s comment said cross-owner entry "is deferred to a future tournament_invites accept flow". I later BUILT that flow and never revisited the gate, so the two halves shipped mutually incompatible. Grep your own deferral comments when you implement the thing they defer to.

## shadcn/ui and Flutter (2026-07-07)
- shadcn/ui is React + Tailwind (.tsx components, `components.json`, npx CLI). It CANNOT be installed into or rendered by a Flutter app. What ports is the *discipline*: semantic CSS-variable tokens -> Flutter ThemeExtension, and the composition primitives (Skeleton / Empty / Alert / Field+FieldGroup / ToggleGroup) as an app-local widget layer. Say this plainly rather than pretending to "use shadcn" in Dart.

## Fixing what an audit found (2026-07-07 fix run)
- **When a fix breaks existing tests, suspect the TESTS first.** Every single break during this run was the fix working: 8 pgTAP files used direct table writes as fixture setup (revoked on purpose), `24-matches-rls` asserted a silent no-op that became a hard denial, `61-compute-innings-cards` expected a bowler to be charged 7 legal balls where only 6 were bowled (a retirement counted as a delivery), and `102`'s cap fixture declared no squad at all. Read the failure as evidence before touching the fix.
- **pgTAP fixture writes that production clients must not have**: wrap in `reset role;` then re-`authenticate_as`. Inside a plpgsql helper that will not work (`reset role` is invalid there and SECURITY DEFINER inherits the CREATING role) - define the privileged helper BEFORE `authenticate_as` so its definer is the session owner.
- **`throws_ok(sql, errcode, description)` is a trap**: the 3-arg form treats arg 3 as the expected MESSAGE. Use `throws_ok(sql, errcode, NULL, description)` when you only care about the code.
- **A server-side patch can fix a client bug without shipping a release.** Turning `edit_ball` from full-overwrite into COALESCE-patch semantics made the already-deployed app stop destroying data, because the columns it never sends are now preserved rather than reset. Look for this shape before assuming an app update is required.
- **Deriving a value from user-supplied data needs a sanity floor.** Deriving `squad_size` from `match_squad` is right, but a squad of 0 or 1 yields `all_out = 0` - an innings over before a ball is bowled. The floor (only trust a declared squad at >= 2) is what made the shared fold helper safe for real data.
- **A constraint that must hold across N copies of an algorithm needs ONE owner.** Three folds each re-derived the same innings parameters and two drifted. `_innings_fold_params()` removes the possibility, which a comment saying "LOCKSTEP RULE" did not.
- **`ref.read()` inside `dispose()` is a Riverpod trap**: once the element is disposed it throws StateError, so the teardown you wrote never runs and you leak exactly what you meant to release. Capture the dependency (or a detach closure) at subscribe time instead.
- **`ref.listen` fires on CHANGE, not on current value.** A screen that only wires itself up from `ref.listen` does nothing when it opens with an already-cached provider - which is the normal entry path. Sync from `.value` as well.
- **Two Realtime channels on one topic is not a supported shape.** Give each topic a single owner (a registry keyed by topic with attach/detach refcounting) rather than letting each screen open its own.
- **Widening `on SomeException catch` to `catch` blindly breaks bodies that use the typed members** (`e.code`, `e.message`). Keep the typed catch for the specific handling and ADD a general catch after it.
- **`flutter build ios` can fail (`xcodebuild error 74`) where a direct `xcodebuild` succeeds.** Flutter passes a custom `BUILD_DIR` inside the project; if that path carries extended attributes (e.g. `com.apple.provenance`, which files under `.claude/worktrees/` do), the build trips on "Failed to remove com.apple.FinderInfo". Diagnose by running `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -sdk iphonesimulator build` directly - if that passes, the app code is fine and the problem is the build directory. Remedy: delete `build/ios`, or build into DerivedData.
- **A "silent failure" comment is a bug marker.** `catch (_) {/* the list refresh reflects reality */}` was wrong on its own terms: on failure the list reflects the UNCHANGED state, so the user sees their tap undone with no explanation. Grep your own reassuring catch comments.
- **THE RIVERPOD INVARIANT (three failed attempts before I saw the class): a SYNCHRONOUS provider must never watch an ASYNCHRONOUS provider.** `Provider<int>((ref) => ref.watch(someFutureProvider).value ...)` and `Notifier.build() => ref.watch(someFutureProvider)` are the same bug. When a widget's FIRST watch happens during build, that watch flushes the async ancestor inside itself; the ancestor yields a value, notifies the sync dependent, and the dependent calls `invalidateSelf` -> `scheduleRefresh` -> `setState` on the ProviderScope MID-BUILD -> "setState() called during build". **Widgets MAY watch async providers (proven: the crash moved past a widget-level watch); an intermediate SYNC provider may NOT.** The fix is to delete the intermediate provider and make the derivation a PURE FUNCTION the widget calls on the value it watched itself.
- **When a crash MOVES to a new line after your fix, you fixed an instance, not the class.** The Discover assertion walked :74 -> :44 -> :70 across three separate providers with identical shape. On the second move, stop fixing and go enumerate every occurrence of the shape (`grep "ref.watch(.*Provider).value"`) before touching anything else.
- **A fix that "looks right" and passes analyze + widget tests can still be the same bug relocated.** Only the device run distinguished attempt 1 from attempt 2 - the assertion simply reappeared at a different line with a different stack. Re-run the device check after every attempt; do not infer success from the unit layer.
- **`ref.listen` inside `build` that MUTATES another provider is a hard crash, not a smell.** Registering the listener flushes the watched provider during the build phase; its notification can invalidate a dependent, which calls setState on the ProviderScope mid-build -> "setState() called during build". Fix by making the target provider DERIVE the value (`ref.watch` inside its own build) instead of having a widget push it in. Only a real device run surfaces this - widget tests with overridden providers never flush the real one.
- **The `(select id from public.X limit 1)` pattern in pgTAP exists because psql does not interpolate `:'var'` inside `$$`-quoting.** The correct answer is `format($$ ... %L ... $$, :'var')`. Left unscoped, guard tests catch the WRONG error (RLS 42501 or 'not authorized' instead of the constraint under test) and pass for the wrong reason.
- **To prove a test-scoping fix, seed a decoy row** that the unscoped query would have picked, then re-run. "It passes" on a clean database proves nothing about the bug you just fixed.
- **`create or replace function` with a different arity CREATES AN OVERLOAD, it does not replace.** Two candidates make every call with the shared arity ambiguous and PostgREST 300s. Always `drop function <old exact signature>` first - and check whether the old parameter should exist at all.
- **Read the screenshots, not the exit code.** A green device run still had a dead end in it: group placement worked, but "Generate group fixtures" sat disabled behind a hint that stated a condition rather than the requirement (the format needs 4 teams; the hint said "2 per group"). Only looking at the captured frame showed the user would be stuck.
- **A widget test that reaches a button via `ensureVisible` can be passing by a one-line margin.** In a lazily-built ListView the off-screen child is never INSTANTIATED, so `ensureVisible` throws "Bad state: No element" the moment any text above it wraps. Use `scrollUntilVisible` for anything below the fold.
- **A form that hides its own requirements is a defect, not a style choice.** Pitch's toss screen gated the whole "Opening pair" section behind the toss being decided, so the first-time scorer's only feedback about openers was a red error naming a control they had never seen. Show the section with a "do X first" hint instead of hiding it.
- **A carelessly-written journey test can be more valuable than a careful one.** Journey D tapped "Start match" with nothing selected - not what a real user does - and that is exactly what exposed the hidden-requirements defect. Do not over-sanitise the happy path; users mis-tap.
- **Never tap a DropdownButton by its hint text in a widget/integration test.** The hint Text sits inside the button but the hit test lands elsewhere; Flutter warns "derived an Offset that would not hit test" and the menu silently never opens, so the later `find.text(option)` fails with a confusing "Bad state: No element". Tap `find.byType(DropdownButton<T>).at(i)` after `ensureVisible`.
- **Never put backticks in a `git commit -m "..."` string.** The shell command-substitutes them and RUNS the contents. Writing a message containing a backticked `supabase db reset` actually executed it - it only failed because the cwd was wrong, and a success would have wiped the database out from under a running integration test. Always use a heredoc (`git commit -F - <<'MSG'`), which also quotes the delimiter so nothing expands.
- **THE STALE-PROVIDER HANDOFF (Riverpod + pushReplacement).** Screen A watches `fooProvider(id)`; A writes to foo; A calls `context.pushReplacement(B)`; B watches the same `fooProvider(id)`. B gets the value A was holding from BEFORE the write. The provider is never disposed because A's listener is released and B's acquired in the same frame, so the ref count never reaches zero. This silently broke the app's core flow - squads saved, toss screen offered no openers, match unstartable. **Rule: any screen that writes X and then navigates to a screen that reads X must `ref.invalidate` X first.** Grep for `pushReplacement` and check each one. `flutter analyze` and every widget test that mocks the provider are blind to it; only the device (or a test whose fake returns DIFFERENT data on the second read) catches it.
- **A widget test that overrides a provider with a constant cannot see a staleness bug** - the override answers the same thing whether or not you invalidated. To test invalidation, make the fake return empty on fetch #1 and real data on fetch #2, then assert on what the user sees. Prove it RED by deleting the invalidate.
- **`find.text` cannot tell an open DropdownButton menu from a shut one.** The button keeps every item in an `IndexedStack` inside itself (to size to the widest), so the item text is in the tree either way. Count matches BEFORE tapping and wait for the count to grow, then assert `button.value` actually changed.
- **`routerDelegate.currentConfiguration.uri` does not reflect an imperative `context.push`.** Asserting on it reports the old location and looks like "navigation didn't happen". Give each test route a screen that renders its own location and assert on that instead.
- **NEVER run `supabase db reset` while a `flutter drive` journey is in flight.** The journeys hit the same local database; a reset wipes the signed-up user and their teams mid-run and the failure looks like an app bug on a screen far from the cause (run 13 reported "guest never added" on a team page that had just been orphaned). Either finish the run first, or do only non-DB work while it goes. Check with `pgrep -f 'flutter drive'` before any reset.
- **A plpgsql guard written `if not (A or B) then raise` NEVER FIRES when A or B is NULL.** `not NULL` is NULL, and `if NULL then` does not execute. This bit the new `leave_team` RPC: a GUEST team_members row has `profile_id` null, so `profile_id = auth.uid()` is NULL and `not (is_admin or NULL)` was NULL - any authenticated user could have removed any guest from any team. Write `if not coalesce(A or B, false) then`. Note RLS `using`/`with check` clauses are SAFE from this (NULL is treated as false there); it is only the procedural `if` that is dangerous. My own pgTAP test caught it, which is the argument for writing the negative-authz assertion every time.
- **`pg_get_functiondef` output has NO trailing semicolon.** Pasting it into a migration and appending anything (a `revoke`, a `grant`) makes the next statement part of the function body and the migration fails with a bare "syntax error at or near revoke". Add `;` after the closing `$function$`. Regenerating a big function from the live definition IS the right way to change one expression inside it - it guarantees the rest stays byte-identical and the three folds stay in lockstep - just terminate it.
- **An alias you introduce inside a regenerated function can collide with one already in scope.** Adding a subquery aliased `d` inside `compute_innings_state` produced "column reference d.innings_id is ambiguous" because the function already used `d` for the delivery cursor. Pick a distinctive alias when patching into someone else's scope.
- **A SIMULATOR iOS build never applies an entitlements file.** It is ad-hoc signed, so `codesign -d --entitlements` returns an empty dict no matter how correctly `CODE_SIGN_ENTITLEMENTS` is set. Verify the WIRING with `xcodebuild -showBuildSettings | grep CODE_SIGN_ENTITLEMENTS` and say plainly that end-to-end proof needs a signed device/archive build - do not report it as tested.
- **Reading the code is still finding real defects that no test tier catches.** This session, `from('teams').select(...)` with no limit (the whole table into a dropdown), an `overs_limit` column with no constraint, and an OAuth redirect scheme registered on neither platform were all found by opening the file, not by any suite. Static review, pgTAP, widget tests and the device each catch a DIFFERENT class; none subsumes another.
- **A modal sheet that opens on success will swallow the NEXT tap in an integration test.** Pitch opens a wagon-wheel "where did the run go?" sheet after every scoring shot; a journey that tapped two run buttons in a row recorded only the first, and the assertion that failed was two steps later and about a completely different thing (a wrong score). When a journey drives a control that can open a follow-up sheet, dismiss it explicitly in the helper rather than assuming the next `tap` lands on the pad.
- **A provider that already SELECTS a field the UI never renders is a strong smell.** `activeTeamInvitesProvider` fetched `invite_token` and the invite list showed only usage and expiry, so a captain could never read back a code they had shared. Grep for selected columns that appear in no widget - each one is either dead weight or a feature someone forgot to finish.
- **postgrest-dart's `order()` defaults to DESCENDING** - the signature is `order(String column, {bool ascending = false, ...})`. A bare `.order('created_at')` reads like "sort by created_at" and silently means "newest first". Seven queries in Pitch were written that way and all seven wanted ascending. ALWAYS pass `ascending:` explicitly, and add a test that greps the source for bare `.order(` - the compiler cannot help here because the code is perfectly valid.
- **A list whose row LABELS are computed by position is only correct if the query order is guaranteed.** The ball log walked the delivery list forward incrementing an over counter (0.1, 0.2, ...) while the query returned newest-first, so every label named a different ball than the row it sat on. Either derive the label from the row's own data, or make the ordering explicit and assert it.
- **"All tests passed" over a wrong screen has now happened twice.** Both times the assertion checked a TOTAL (a score, a count) that was correct while the ARRANGEMENT was wrong. When a journey asserts an aggregate, add one assertion about structure - the order of a list, which row carries which label - or look at the frame.
- **Riverpod's `AsyncValue.when()` defaults `skipLoadingOnReload` to FALSE.** A sync provider that does `.when(loading: ...)` over an async one therefore reports loading whenever a WATCHED DEPENDENCY changes, even though it is still holding a good value. In Pitch this meant every JWT auto-refresh flipped the auth gate to loading and the router tore the whole navigation stack down to a top-level splash route. If a sync provider must consume an async one, pass `skipLoadingOnReload: true` - a reload is not a cold start.
- **A test that models an async bug needs a real async gap.** My first auth-gate model resolved its future immediately, so the reload finished inside one microtask batch, the intermediate loading state was never observable, and the test passed for both the buggy and fixed configurations - proving nothing. Adding a 5ms delay made the mechanism visible. Always include a case that OBSERVES the bug, not just one that observes the fix.
- **Never write a comment asserting behaviour you have not exercised.** I shipped a create-profile "Sign out" with the comment "the router lands them on Discover"; the router did no such thing, and the comment made the gap look intentional and verified to the next reader. If you cannot test it now, write what you did NOT verify.
- **A soft-delete tombstone is not one change, it is a change to every query that asks "is this thing present?"** Adding `left_at` to team_members took one migration; making it CORRECT took a second one touching five more functions, because accept_invite, request_to_join, add_guest_member, transfer_scorer and the last-captain guard all asked that question and none of them filtered. The failure mode was the worst kind - accept_invite returned the dead row and the app reported "You joined the team" over a complete no-op. When introducing a tombstone column, grep every read of that table in the same unit and decide, per query, whether it means "ever" or "now".
- **Design the reverse path at the same time as the forward one.** Leaving a team was implemented; rejoining was not, so leaving became irreversible. Any state transition a user can perform should be considered with its inverse in the same change - especially when the forward one leaves a durable marker behind.
- **When two review agents disagree about a finding, run the scenario.** One dimension confirmed the last-captain guard counted departed captains and another refuted it; writing the actual test settled it (already correct in the reachable case, because leave_team refuses to let the last captain leave). Report that as hardening, not as a bug fixed.
- **`findsOneWidget` cannot detect a DEAD control.** Journey D asserted Undo/Swap strike/Retire were present, naming the AbsorbPointer regression that had made them unresponsive - but that regression left them fully rendered, so the assertion could never have caught it. To test that a control WORKS, assert the state it changes (tap Swap strike, then assert who is on strike is different), never its existence.
- **Waiting for something that is always on screen is a no-op, and it hides the absence of any real assertion.** Journey B did `settle(find.text('Discover'))` after posting - that is the tab label, present the whole time, so it returned instantly and the journey never checked the post existed. When writing a wait, ask what is on screen BEFORE the action; if the finder already matches, the wait proves nothing.
- **A finder for text the test just TYPED will match the input field.** Journey C searched for a player and asserted `find.textContaining(name)` - satisfied by the search box, so it passed with zero results. Scope result assertions to the result container (`find.descendant(of: find.byType(ListTile), ...)`).
- **A guard test can pass for the wrong reason when two rules can each exclude the row.** pgTAP 112 claimed to prove the match-date floor hides a past match, but the post was also already expired, so the floor was never exercised. When asserting rule A excludes something, make every OTHER rule explicitly non-excluding first - and add an assertion that says so.
- **A bound assertion needs a fixture that EXCEEDS the bound.** `count(*) <= 25` with one row in the table passes with no limit implemented at all.
- **Put a form's error message ABOVE its submit button, not after it.** The submit button is usually the last widget in a scrolling form, so an error rendered after it appears below the fold: the user taps, the screen does not move, and the explanation is off-screen underneath the button they just pressed. Seven Pitch forms had this. It reads exactly like a dead button.
- **Fixing a dud assertion found a real bug within one run.** Journey B's wait had been `find.text('Discover')` - the tab label, on screen always - so it never checked anything; replacing it with a wait for the actual post revealed that the journey had NEVER created a post (it never picked a required flair) AND that the composer's failure message was invisible. When a test has been green for a long time over a path you have never watched, distrust it before you trust it.
- **A scroll-to-find test helper must search BOTH directions.** Pitch's `tapScrolled` only dragged downward, so anything above the current scroll offset was unreachable - journey B hunted for the flair chips near the TOP of the composer, scrolled to the very bottom, and failed with a screenshot of the end of the form, which reads like "the control is missing" rather than "I looked the wrong way".
- **Check what a control actually IS before writing a finder for it.** The composer's flair options look like chips but are `FlairChip` widgets inside a `GestureDetector`, not `ChoiceChip`, so `find.widgetWithText(ChoiceChip, ...)` could never match. Grep the widget in the source rather than inferring its type from the screenshot.
- **When every layer supports a field except the input, you have a feature that was never finished.** Pitch's `looking_for_posts.title` existed, the RPC took `_title`, the feed query returned it, and the card PREFERRED it as its headline - but no composer field ever set one, so every ad in the feed read "Need a team" instead of the poster's own words. Trace a column end to end (schema -> RPC -> query -> widget -> INPUT) before assuming it works; the missing end is usually the input.
- **Journey assertions that reference a field by label will silently skip if wrapped in `if (finder.evaluate().isNotEmpty)`.** That guard was hiding the fact that the composer had no Title field at all. If a step is essential to the journey, do not make it conditional - let it fail loudly.
- **`pumpAndSettle timed out` in an integration test almost always means a spinner that never stops, not a slow machine.** A `CircularProgressIndicator` animates forever, so the tree never goes idle. Read it as "some provider never resolved" and go looking for the stuck future, not for a timing tweak.
- **Row counts in the database are a fast, honest way to tell how far a failed journey run actually got.** After run 23, `1 user / 2 teams` immediately proved journey A had created its teams while journeys B-K never even signed up - far more informative than the log's failure list.
- **Do not diagnose a hang as "the daemon is dead" until you have measured it.** I called docker hung because `supabase status -o json` was slow and my probes queued behind it; the stack was healthy the whole time and answered a REST query in 66ms. State the measurement, then the conclusion.
- **A helper that gives up silently hides the bug it was meant to expose.** `ensureSignedOut` polls for the 'Sign in' call to action and then RETURNS WITHOUT FAILING if it never appears, so a broken sign-out looks like a failure in whatever step comes next. Test helpers should fail where the problem is.
- **Do not launch a device/integration run immediately after `supabase db reset && supabase test db`.** The test run hammers the local stack; the app's first queries then hang, every spinner outlives `pumpAndSettle`, and you get a run that looks like a catastrophic regression (run 23: six failures across five journeys, 67 minutes) when the next run is clean in under seven. Let the stack settle, and never conclude "regression" from a single bad run.
- **One green run is not stability.** After a mass failure, re-run at least twice before recording the earlier failure as transient - and write down what was different about the bad run, so the same trigger is recognisable next time.
- **A journey that stops one item short of a threshold never tests the threshold.** Journey A added two teams to a tournament that needs four, so `Generate group fixtures` - the step that makes a tournament playable - was never once exercised on a device, and the gating copy promising "you need 4 teams" was never checked against reality. When a feature has a minimum, write the journey that REACHES it.
- **Assert a disabled control is disabled, not just present.** The honest failure mode for a gated action is "enabled, then fails" or "stuck disabled forever". Reading `button.onPressed == null` alongside the explanatory copy pins both directions; `findsOneWidget` pins neither.
- **I have now made the `if (finder.isNotEmpty)` mistake TWICE after writing it down.** Knowing an anti-pattern is not the same as not reaching for it: the guard is seductive because it makes a step "robust" to layout changes, and what it actually does is convert "the control is missing" into "the step passed". Rule with no exceptions: in a journey, a step that MUST happen gets an unconditional tap. If you want tolerance, assert the outcome afterwards instead.
- **Assert the SCREEN's own summary back, not just your taps.** Journey G now waits for the tournament's own line "A has 2 and B has 2" after splitting the groups. The app already computes and displays the thing you are trying to establish - reading it back is a far stronger check than believing four taps landed.
- **A positive assertion must name a string that actually exists.** I asserted `find.textContaining('Fixtures')` after generating; the heading is "Group fixtures" and nothing renders the bare word. Grep the widget source for the literal before asserting on it - a positive assertion that names nothing is just a slower dud.
- **"Read the screen's own summary back" has a corollary: read the summary that exists in the state you are asserting.** Pitch's tournament screen prints "You need 4 teams to start: ... A has N and B has N" ONLY while the requirement is unmet. Waiting for "A has 2 and B has 2" was waiting for a string that vanishes at the exact moment of success. For a satisfied precondition the signals are usually the opposite: the warning DISAPPEARS and the gated control becomes ENABLED.
- **Count whose bugs a new test is finding.** Journey G took three iterations and every failure was a mistake in the test, not the app - wrong widget type, a silent guard, and then an assertion on a string that only exists in the failure state. That is normal for a new journey against unfamiliar UI, but it is worth saying out loud rather than letting three red runs imply the product is broken.
- **A test that models a provider's SHAPE cannot see that provider losing its fix.** `auth_gate_reload_test.dart` reimplemented the gate's `.when()` call locally to make the async behaviour observable - a reasonable technique - but that meant deleting `skipLoadingOnReload: true` from the real `authGateProvider` left the test green. Model tests pin MECHANISMS; they do not pin the production call site. When a one-line argument IS the fix, add a source guard that reads the file, exactly like the postgrest ordering guard.
- **Before reporting a file as changed, re-read it and check `git diff`.** I announced that a critical line had been deleted based on one grep and a `git status` that showed modified; moments later the line was present and the diff was empty - I had caught the file mid-write. Two cheap confirmations (re-grep, `git diff --stat`) would have prevented a false alarm.
- **"The RPC holds the rule, but the TABLE is still granted" is a CLASS, not an incident.** Pitch had a migration written specifically to hunt that shape; it fixed one table, explicitly noted it was leaving `matches` INSERT alone, and that became the next review's CRITICAL. When you find one instance, enumerate every table/function with the same grant shape in the same commit - and then encode the invariant as a test, because an audit only covers the afternoon you did it.
- **An RLS policy of the form `owner = auth.uid()` proves WHO is writing, never WHAT they may write about.** It is correct only for self-scoped rows where the row IS the caller (a profile, a reply). For anything referencing other entities - a match between two teams, a fixture, a membership - the policy must also assert the caller's relationship to those entities, or the row's other columns are attacker-controlled.
- **When a review's output file may be garbage-collected, persist it before doing anything else.** I lost the per-finding confirmed/refuted split of an 18M-token review because I read the notification, started fixing, and came back to a deleted task file. The journal saved the finding text but not the verdicts. Persist first, fix second.
- **Gradle evaluates `buildTypes.release { }` at CONFIGURATION time, for every invocation.** A `throw` inside it fires on `assembleDebug` and `flutter run` too. Guards that should only apply to release artifacts belong in `gradle.taskGraph.whenReady`, checking the actual task graph. Pitch shipped a keystore guard this way and it broke every build for anyone without the keystore.
- **Reading the top of a config file is not reading the file.** I almost refuted the Android build CRITICAL because build.gradle.kts opens by loading key.properties conditionally, with a comment about falling back - the throw was 40 lines further down. For build files especially, read the whole thing or run the command; a partial read produces confident wrong answers.
- **Detaching a user from their rows can silently make those rows CLAIMABLE.** Pitch's account deletion set `profile_id = null` + a guest name so scorecards still render - which is exactly how the app defines an unclaimed guest that anyone may claim. Whenever a delete/anonymise path produces a row shaped like some other feature's input, check what that feature will now do with it.
- **The same rule enforced in one exit path and not another is a door left open.** `leave_team` guarded the last captain; `delete_my_account` did not, so the identical harm was one screen away. When a rule protects an invariant, enumerate EVERY path that can reach that state, not just the obvious one.
- **A config-check helper nobody calls is worse than none** - it reads as covered. `SupabaseEnv.googleConfigured` knew exactly which client ids each platform needs and no screen ever asked it, so iOS offered a sign-in that could not complete. Grep for callers of any `isConfigured`/`isAvailable` helper you find.
- **Never `git add -A` a directory you have not just inspected.** Review subagents left three probe files in `test/`, I staged them blind, and the widget suite went from 8 SECONDS to 30 MINUTES with 6 failures - one probe rasterised a share card at pixelRatio 3 and asserted nothing. `git status --porcelain <dir>` before staging costs one command.
- **Not every leftover probe is garbage - read it before deleting.** Of the three, two were assertion-free printouts and were rightly deleted; the third had 11 real assertions covering a genuine finding and was worth promoting to a permanent test. Deleting all three by name pattern would have thrown away real coverage.
- **A cached provider failure turns a transient network blip into a permanent dead end.** Riverpod holds the error, so a bare `error: (e,_) => Text(...)` branch means reopening the screen shows the same stale failure. Every async error branch on a screen a user cannot abandon (a live scoring console) needs an explicit retry that invalidates the provider - and should say what is NOT lost.
- **A policy subquery is evaluated as the CALLING user, so it silently returns NULL for rows they cannot SELECT.** Pitch's block-the-reply policy read the post's author with a plain subquery; `looking_for_posts` is own-rows-only (posts are read via an RPC), so for anyone else's post it yielded NULL, `is_blocked_between(NULL)` was false, and the guard never fired. Any lookup inside a policy that crosses into a table the user cannot read must be SECURITY DEFINER - and wrap the whole condition in `coalesce(..., false)`. That is now the THIRD distinct NULL-disables-a-guard bug in this project.
- **A COALESCE-patch RPC cannot express "remove this".** `edit_ball` keeps any field you omit, so passing null for a wicket did nothing; the RPC had explicit `_clear_*` flags and the client never sent them. When an API is patch-shaped, every nullable field needs a paired clear flag AND a test that the omit-case KEEPS the value - otherwise the clear test looks like a tautology and nobody notices the client half is missing.
- **A screen fed only by push needs at least one pull.** The live match viewer re-folded exclusively inside a realtime broadcast callback, so one missed message froze it forever. Anything driven by a socket needs recovery on resubscribe, on app resume, and a manual refresh - the interesting failure is precisely when the socket is what broke.


## 2026-08-04 - counters, controls, and sheets that run off the screen

- **A modulo test on a counter cannot tell "just arrived" from "already there".**
  `legal % 6 == 0` meant to catch "this ball ended the over" also fires on every
  delivery that does not move the counter (a wide, a no-ball) whenever it is
  already sitting on a multiple - which it always is right after an over ends.
  The fix is never a smarter modulo, it is comparing against the value from
  before the event. Look for this shape anywhere an edge is inferred from a
  counter's value instead of its change: over boundaries, page boundaries,
  "every Nth" triggers, batch flushes.
- **If a fix could be satisfied by deleting the behaviour, prove the control
  discriminates.** "The bowler must not be cleared on a wide" is satisfied by
  never clearing the bowler, which breaks cricket. Sabotaging the fix to the
  lazy version and confirming the CONTROL test goes red - while the bug tests
  stay green - is what proves the suite pins both directions. Cheap: two
  minutes and a `cp` backup.
- **A `tap()` on a widget below the test viewport does not throw, it hits
  nothing.** The 600pt test window is much shorter than a phone, so a bottom
  sheet that fits in real life still overflows in tests; the tap lands on the
  barrier and the assertion fails far away with "recorded 0 calls". `tap()` only
  prints a "would not hit test" warning. Check whether the sheet actually
  SCROLLS (drag it) before concluding it is a real layout bug - here it scrolled
  fine and the finding was a test artifact, so `ensureVisible` was the right fix
  rather than changing the app.
- **Half a recorded finding can be true.** "The app cannot record a dismissal
  off a wide, and the backend accepts illegal ones" was two claims; the server
  half was already correct. Re-verify each half separately - fixing the true
  half and writing a characterisation test for the refuted half is the right
  outcome, not a blanket "confirmed" or "refuted".
- **Measure fan-out, do not estimate it.** "insert_ball emits 2 broadcasts per
  shifted delivery" was recorded as a finding; counting `realtime.messages`
  around one call showed 71 for a 30-ball innings (and 15 for a delete, 1 for an
  ordinary ball). The count is trivially observable and the real number reframed
  the fix. Any AFTER ... FOR EACH ROW trigger on a table an RPC bulk-renumbers
  deserves this check.
- **When suppressing noise, the control is the load-bearing test.** Silencing a
  broadcast is a one-line change that can silence EVERYTHING; too quiet is worse
  than too noisy, because the viewer then never learns anything. Pin "the
  ordinary path still emits exactly once" before touching the noisy path.
- **`set_config(..., is_local => true)` is the right scope for "quiet during
  this RPC".** It unwinds with the transaction, so it cannot leak across a
  pooled connection and it self-clears if the function raises partway through -
  no need for an exception handler to reset it.
- **A soft delete is often only half the story - check when the code hard-
  deletes instead.** `leave_team` tombstones a member who has match history and
  DELETES one who does not. A rejoin test written with a player who never played
  exercised the delete path, passed against the broken function, and nearly
  cleared a real bug. Before testing tombstone behaviour, verify the fixture
  actually produces a tombstone.
- **`on conflict ... do nothing` is a silent-failure generator wherever soft
  deletes exist.** The row is there, so nothing happens, and the caller's own
  status update ("approved") lands anyway - so the UI reports success. Audit
  every `do nothing` against a table that has a `deleted_at`/`left_at` column.
- **`do update ... where <target>.col is not null` is how you confine a revival
  to tombstones.** Without the WHERE, the upsert rewrites live rows too - here
  it would demote a sitting captain. Sabotage-test the guard; an unguarded
  version still passes the happy-path assertions.
- **When the server relaxes a rule, the client must ASK, not re-derive it.** The
  bowler quota was computed in two places: the app stamped `ceil(overs/5)` and
  the server enforced `greatest(rule, ceil(overs/squad_size))`. The client copy
  was stricter, so the UI dead-ended matches the backend would happily have
  accepted. Any rule with two implementations will drift; the one that matters
  is the server's, so expose it and read it.
- **`ref.read` on a FutureProvider nobody watches returns null while it loads.**
  Reading a cap/flag lazily inside an on-demand sheet therefore silently means
  "unset" on first open. Watch it where the data is already in scope and pass
  the resolved value in.
- **Read the actual pass/fail line, not the tail of `flutter test`.** The tail
  is the FAILURE LIST, which looks like ordinary test names. Grep for
  `All tests passed|Some tests failed` - a commit went out claiming a green
  suite that was 288 +2 red because the tail read like success.
- **Recovery logic belongs on the DATA, not in the handler that happened to
  need it first.** The console resumed a mid-over bowler inside `_undo()`, so
  undo worked and every other route to the same state - ball-log delete, insert,
  another device over realtime - was stranded. A `ref.listen` on the fold covers
  all of them, because the fold is the one thing they all move. Ask "what else
  can produce this state?" before writing the fix into one callback.
- **Deleting working code needs a regression guard, and the guard must be shown
  to depend on the replacement.** After moving the recovery, an undo test
  passing proves nothing on its own - it might pass for an unrelated reason.
  Sabotage the NEW mechanism and confirm the old-route guard goes red with it.
- **Reactive state changes need a driveable source in tests.** A static provider
  override cannot express "the fold said 6, then said 5 again". A small
  `Notifier<int>` the override watches, plus a fake repo that moves it, models
  ball-then-correction faithfully - and the same harness then covers undo.
- **Assert the PLANNER USES an index, never that the index exists.** "There is
  an index on display_name" passes happily while every keystroke seq-scans,
  because no btree can serve `ilike '%q%'`. Run `explain (costs off)` with
  `set local enable_seqscan = off` and match the index NAME in the plan. Turning
  seqscan off does not force an index scan - where none applies Postgres still
  seq-scans - which is exactly what makes the assertion discriminating.
- **"Add a LIMIT everywhere" is its own bug.** A match squad is eleven rows and
  an innings a few hundred deliveries; capping those silently drops players off
  a scorecard. Only cap sets bounded by nothing the user can see. Guard BOTH
  directions so the next person cannot over-correct.
- **A source-scanning guard must be proven to still be looking at something.**
  Mine truncated a builder chain on a `;` inside my own comment, and anchored on
  a bare `from('innings')` that matched a single-row `.limit(1).maybeSingle()`
  lookup rather than the list query. Strip comments before scanning, anchor on
  something unique to the statement, and assert the anchor was found.
- **Capping is not paginating.** Say so in the commit and the code when the fix
  trades unbounded download for lost reach, instead of letting a LIMIT read as
  a solved problem.
- **A table-level GRANT is not fronted by an RPC.** Comments in two separate
  migrations claimed "delete_match fronts it" / "the scorer writes through
  record_ball" while `grant ... to authenticated` was still in force. If every
  writer is SECURITY DEFINER, REVOKE the grant - that is the only thing that
  makes the RPC the sole door. Check `information_schema.role_table_grants` for
  the client roles whenever an RPC carries the real business rules.
- **Revoking a grant surfaces every test that was quietly using it.** 28 pgTAP
  files seeded via direct INSERT. The fix is elevate-for-the-seed then RESTORE
  the previous role (`select current_role as _r \gset; set local role postgres;
  ...; set local role :_r;`) so later assertions still run as the intended user.
  Inside plpgsql, SET ROLE back to the SESSION user is still permitted; a
  `security definer` temp function does NOT help if it was created after
  authenticate_as, because it is then owned by `authenticated`.
- **After a permission change, grep the DEVICE JOURNEYS too.** A walkthrough was
  seeding deliveries by direct insert while its own comment claimed it used the
  RPCs. Widget tests and pgTAP both stayed green; only the next simulator run
  would have caught it.
- **GENERATED ALWAYS columns are rejected by the parser before permissions.**
  An assertion that writing one is "permission denied" tests nothing - the error
  is 428C9, and the column was never writable. Pick a plain column when the
  point is the grant.
- **When a hardening run hides the front door, check the side doors it left.**
  SEC-2 revoked the blanket read on looking_for_posts and moved reads behind
  definer RPCs - but left post_replies `using (true)` and a by-id resolver with
  no gate. The asymmetry is the tell: if one read path got a rule, every read
  path onto the same data needs it. Enumerate them before calling it hardened.
- **On a tightening fix, the CONTROLS are the deliverable.** Blocking a leak is
  one line; not breaking the product is the hard part. Finding 63's test is 2
  block assertions and 7 controls (feed still resolves, strangers can still
  reply, author keeps their closed ad, repliers keep the thread). A tightening
  commit with no controls should not be trusted.
- **Check enum labels against the database, never memory.** Guessed
  `players_needed`/`casual`; the real labels are `team_seeking_players` and
  `practice_match`. This is the SECOND time an lf_ enum guess has cost a run -
  `select unnest(enum_range(null::public.<type>))` first, every time.
- **storage.objects cannot be DELETEd from SQL.** Supabase installs a trigger
  that rejects it - "Direct deletion from storage tables is not allowed. Use the
  Storage API instead" - because removing the row would orphan the actual file.
  Any "delete the user's uploads" work has to run through the Storage API from a
  client or an Edge Function, never a migration.
- **Order matters when a cleanup needs the identity it is about to destroy.**
  delete_my_account revokes the auth rows, so the Storage API can no longer act
  as that user afterwards. Photos must be removed FIRST, and the failure must
  NOT be swallowed: an account still present can be deleted again tomorrow, a
  photo whose owner no longer exists cannot. Same shape for any revoke-then-
  cleanup sequence.
- **When the UI states a promise in words, that sentence is a spec.** "This
  permanently removes your profile, posts and messages" is testable, and it was
  false for two of the three nouns. Grep user-facing promises and check each
  clause against what the code does - and when the code is right but the
  sentence is short, fix the sentence too.
- **A cramped bottom sheet in a widget test is usually the 600pt viewport, not
  the app.** The test window is far shorter than a phone, so a sheet that needs
  scrolling there can be comfortable on device. Confirm by dragging (does it
  scroll?) and by LOOKING at a device frame before changing layout - here the
  fix was `ensureVisible` in the test, and the real screen had room to spare.
- **Re-seed after every `supabase db reset` before any device run.** Six resets
  this session wiped dev@pitch.local each time; the journeys sign in as that
  user and would fail for a reason that has nothing to do with the code.
  Admin API POST /auth/v1/admin/users, then insert the profiles via psql.
- **"Who else is now the sole holder of a permission?" is a repeatable audit.**
  The sole-captain freeze and the orphaned-tournament freeze are the same bug in
  two places: an entity whose only administrator is one account, with no
  transfer path and no handover on deletion. Grep for `= auth.uid()` gates on an
  owner column and ask what happens when that account leaves - teams and
  tournaments both failed it, and both took the identical fix.
- **Test fixtures must use the real entry path.** `add_tournament_team` requires
  the caller to be an admin of the TEAM as well as the organizer, so a club
  actually enters by token (create_tournament_invite +
  join_tournament_with_token). Guessing the shortcut cost a run; the error
  message named the exact gate.
- **Riverpod 3 FutureProvider is NOT autoDispose by default, and that is a bug
  wherever the family key is free text.** An id-keyed family should cache - that
  is the point. A query-keyed family must not: every prefix typed leaks, and a
  failure is cached as a failure, so retyping the same string never retries. The
  guard should encode that LINE, not "everything must be autoDispose".
- **Test the property the user feels, not the keyword.** For autoDispose that
  means: listen, drop the subscription, read again, assert the work ran twice.
  Asserting the source contains "autoDispose" would pass on a provider that is
  never actually released.
- **Verify build config in the MERGED manifest, not the source one.** Any plugin
  can override an application attribute during manifest merging, so
  `build/app/intermediates/merged_manifests/.../AndroidManifest.xml` is the only
  file that reflects what ships. Check the resource landed in the APK too
  (`unzip -l`).
- **Android `allowBackup="false"` is only half the opt-out since Android 12.**
  Device-to-device transfer is governed separately by `dataExtractionRules`;
  exclude every domain from BOTH `<cloud-backup>` and `<device-transfer>`. A
  guard that only checks allowBackup passes on a half-open configuration.
- **A partial exclusion is the dangerous state, so test for it.** Dropping just
  `sharedpref` still ships the Supabase session while the config looks
  deliberate. The guard asserts each domain in each channel rather than that the
  file merely exists.
- **A radius clamp is not a row bound.** discover_posts clamped distance to
  50 km and returned every matching row inside it. Whenever a query is
  "bounded" by a filter, ask what the worst-case ROW COUNT is at that bound.
- **`geog_coarse` is not generated and has no trigger.** create_looking_for_post
  sets it via `_snap_geog(lat, lng)`, and discover_posts filters on it - so a
  fixture that writes only `geog` returns an empty feed, which looks exactly
  like the thing under test failing. Seed both columns.
- **When a bound is added to a list, the ORDERING control is the real test.**
  Capping a feed without preserving nearest-first turns "games near you" into
  "an arbitrary hundred" - a worse bug than the unbounded read. Assert the order
  survives, and check that assertion passes both with and without the cap.
- **Parse what the app actually SHARES, not a tidy version of it.** The
  tournament invite message is two sentences with a newline, so everything after
  the URL marker is "token + newline + another sentence" - and that survives as
  a single URI segment, so the screen loads and blames the invite. Test the
  exact string the app generates.
- **Validate the DERIVED value, not the raw input.** The empty-check ran against
  what the user pasted, so a trailing-slash link passed the guard and pushed an
  empty token. Any "extract then use" pair needs the check on the extracted
  side.
- **Read the analyze VERDICT line, not the tail.** Committed "analyze clean"
  while it said "2 issues found" - the same class of slip as reading the tail of
  flutter test. Grep for `No issues found|issues found` explicitly.
- **When one function treats a value two ways, the bug is inside it.** Each fold
  read `wicket_type in ('run_out','obstructing')` for WHO is out and
  `= 'run_out'` for WHICH END they stand at, twenty lines apart. That internal
  disagreement is a stronger signal than any cross-file grep - when a predicate
  appears twice in one body with different membership, one of them is wrong.
- **A UI that collects a field the backend ignores is a silent-corruption
  shape.** The scorer answered "did they cross?" correctly, it was stored, and
  the derivation discarded it. Worth grepping for: fields the client sends that
  no fold or RPC branch reads.
- **A guard copied between RPCs carries assumptions that may not hold there.**
  retire_batter's "last wicket needs no incoming batter" came from record_ball,
  where it is safe because the wicket ends the innings. A retirement counts no
  wicket, so the same relaxation produced a state the folds cannot represent.
  When lifting a condition, re-derive WHY it was safe in its original home.
- **A validation hole and a dead control are often the same bug from two
  sides.** The server accepted a last-pair retired-hurt it could not represent,
  while the client disabled Retire entirely whenever the incoming dropdown was
  empty - so the invalid case was reachable and the VALID one was not. Fix both
  ends or the scorer just meets a different wall.
- **When an error message changes, a test that pins its text will fail while the
  behaviour is fine.** Read the diff before "fixing" anything: here the old
  wording ("this is not the last wicket") was itself the misleading part, so the
  test was updated, not the code.
- **When a test's DESCRIPTION states a rule, check the rule, not just the
  number.** 30-fold-extras said "bowler conceded = 8 (byes/leg-byes never
  charged)" - a blanket claim that the Laws make true only for a legal
  delivery. The implementation and its test encoded the same misunderstanding,
  which is exactly how a bug survives a green suite. A parenthetical
  justification in a test name is an assertion too.
- **Say out loud when a fix rests on domain judgment rather than on the code.**
  The no-ball attribution follows from Law 21.13, not from anything observable
  in the repo. Flag it, cite the law, keep the change small enough to revert,
  and invite the person who actually scores cricket to check it.
- **A wrong TOTAL gets noticed; wrong ATTRIBUTION does not.** The innings score
  was right the whole time - only the bowler's figures and the extras breakdown
  were wrong, so nobody saw it. Where a quantity is split across buckets, test
  the buckets, not just the sum.
- **A latch set BEFORE the await turns one failure into a permanent one.**
  `_breakMarked = true; repo.write().catchError((_) {})` never retries and never
  speaks. Set the latch AFTER success, or reset it on failure - and if resetting
  would let a rebuild re-fire the call, surface a retry the user drives instead.
  Silence and a request storm are both wrong; a visible one-tap retry is not.
- **"Purely presentational" is worth checking against what reads it.** The
  innings-break write was dismissed in a comment as cosmetic while being the
  only thing three public surfaces use to decide between "Live now" and
  "Innings break". Grep for readers before believing a write does not matter.
- **Changing user-facing copy breaks tests that pin it - budget for that.**
  Three separate commits this run needed an existing test updated because it
  asserted a label or an error string verbatim. That is the guard working, not
  a nuisance: check the diff, confirm only the copy moved, then update the test.
- **When a control cannot express a case, say so in the control.** Penalties
  against the batting side are unmodelled. The options were to invent a schema
  under a LOW bug fix, or to make the UI stop implying support. Naming the
  unsupported case in the copy is honest and cheap; silently leaving help text
  that reads as permission is what caused the bug.
- **"Tap X" in an error message is a promise that X exists.** Three separate
  dead ends this run - copy naming a missing control, a framework default
  offering a route the app never defined, and a stale provider leaving an action
  visible after it had been taken. Worth a periodic sweep: for every
  instruction the UI gives, does the thing it names exist and do something?
- **A framework's default error screen is not free.** go_router's Page Not Found
  looks finished and its only button pushes '/', which an app with a splash
  route does not have. Any router/error default that ships a control should be
  checked against the routes that actually exist.
- **Re-read a finding before deferring it.** I parked finding 70 as "needs a UI
  design decision". It contained a second half - the composer publishes the ad
  geotagged to the guessed city - which is permanent data corruption and needed
  no design input at all. The deferrable part and the urgent part were in the
  same paragraph.
- **`AsyncValue.value` collapses error into absent, and that is a bug wherever
  the two mean different things.** Null-from-error and null-from-unset took the
  same fallback path here. Where a fallback is a guess, check `hasError`
  separately - and never write a guess into stored data.
- **"Work down the findings" needs the findings ENUMERATED, not remembered.**
  I worked review #2 from a mental subset and reported the list complete when
  30 of 87 were still open. The fix was a per-finding audit file on disk with
  CLOSED/REFUTED/USER/OPEN and a commit against each. Do that at the START of a
  long fix run, not after claiming it is finished.
- **The best control is often an EXISTING test you did not write.** pgTAP 76
  pins NRR for a 6-ball tournament; leaving it green proved the balls_per_over
  fix was a no-op at six. Before building a control, look for the test that
  already asserts the case you must not break.
- **Sabotage is the only proof a test works.** Four tests in this suite were
  green for reasons unrelated to the app - a copy of the mapping, a constructor
  tearoff, the test's own arithmetic, an empty result set. None was obvious from
  reading it. Break the thing the test names and watch it go red; if it does
  not, the test is decoration.
- **`is not distinct from` and `is(null, null)` pass on two empty results.** Any
  pgTAP assertion that compares two queries needs a POSITIVE CONTROL first
  (count = 1) or a regression that returns nothing makes the whole file green.
- **A test whose stated REASON is wrong is as bad as one that cannot fail.** I
  wrote "the radius floor defeats a pinpoint probe", sabotaged the floor, and my
  own new test passed - the real protection is grid-snapping both points.
  Sabotage checks the rationale, not just the assertion.
- **Assert the observable that matches WHAT CHANGED.** I asserted the over moved
  after Undo; it did not, and that was correct - the last write was a strike
  swap, an EVENT row rather than a ball, so it moves neither over nor score.
  Before writing a before/after assertion, ask what the operation actually
  touches. A failing test is not automatically a found bug.
- **`if (finder.isNotEmpty)` in a journey is how a broken step stays green.**
  It hid journey G's group split entirely. Replace with an assertion: if the
  control is missing, everything after it is meaningless anyway, so failing
  loudly costs nothing and silence costs the whole run's credibility.
- **A discriminating assertion can sometimes be proven by LOGIC, not another
  run.** Journey D asserts the striker changed after a swap and is restored
  after the undo; a no-op undo cannot satisfy both. That is airtight without
  spending nine minutes re-driving the simulator.
- **Before "fixing" a derivation, check whether the input was supposed to be
  possible.** all_out = squad_size - 1 looked wrong for a 13-man squad, but the
  backend supports variable squad sizes on purpose. The bug was upstream: the UI
  let a scorer choose a format without knowing it. Correct the layer that made
  the choice invisible, not the arithmetic that honoured it.
- **A warning that fires on the normal case is worse than no warning.** Hence
  the control asserting an ordinary XI stays silent - and it catches an
  off-by-one in the threshold, which is exactly how these degrade into noise.
- **Don't store a host you don't control.** photo_url/logo_url/image_urls held
  full URLs, so whoever wrote the row chose the host every viewer's device would
  contact. Storing the PATH and resolving against the app's own configured
  origin removes the attacker's choice entirely - far stronger than validating
  the string, because "starts with https and looks like our path" is trivially
  forged on someone else's domain.
- **Validate that the referenced object EXISTS, not just that the reference
  looks right.** Shape checks are the security equivalent of a comforting
  assertion. Pair the format rule with a lookup against the table that actually
  holds the thing.
- **A user-supplied URL rendered in a list is a beacon, not a cosmetic field.**
  Every render is an outbound request carrying the VIEWER's IP and user agent.
  Worth checking any column that ends up in Image.network / NetworkImage.
- **A one-way status write needs the way back.** matches.status went
  live -> innings_break with no path home except start_innings, so any
  correction that reopened the innings stranded it. When adding a state
  transition, ask what reverses it and who notices - here the client latch made
  the one-way trip permanent as well.
- **A status-repair RPC must consult the source of truth, not just set the
  value.** resume_from_innings_break asks the fold whether the innings is
  actually in progress; a blind `set status = 'live'` would let a scorer drag a
  finished match back. The control asserting a COMPLETED innings stays at the
  break is what separates the two.
- **When one query filters tombstones and another does not, a row can become
  unreachable from both sides.** The squad picker hid `left_at is not null`
  while the duplicate check counted it, so a departed guest was invisible to
  selection AND blocking by name. Whenever a soft-delete exists, check EVERY
  reader agrees on whether tombstones count.
- **Third time this run: soft delete plus an unfiltered uniqueness check.**
  respond_join_request (31), add_match_guest (54), and the same shape nearly bit
  the claim flow. The pattern is `on conflict`/`if exists` against a table with
  `left_at`/`deleted_at` - grep for it rather than waiting for the next report.
- **A "unique" id built from `millisecondsSinceEpoch % 1000000` repeats every
  1000 seconds.** The device journeys drew account ids that way, so two runs
  ~17 minutes apart collided, sign-up returned 422 "user already registered",
  and the journey died at onboarding with no clue why. It cost two false
  regression hunts (I re-read fresh code looking for a break that was not
  there). When a device run fails at a step the code did not touch, check the
  ENVIRONMENT first: the fixture ids, the auth rate limits, and whether I reset
  the database under a live run - which I also did, twice.
- **An overridden provider that throws never delivers its error in a widget
  test.** `myTeamsProvider.overrideWith((ref) async => throw ...)` plus
  `ref.read(p.future)` resolves at container teardown with "disposed during
  loading state", not the exception. The un-overridden provider behaves
  correctly, so this is a test-harness artifact - do not conclude the app is
  broken from it. Fake the REPOSITORY instead of the provider when the code
  under test awaits a future.
- **Riverpod 3 retries a failed provider on its own with a growing backoff.**
  That is a safety net, not a retry button: the user is still looking at an
  error with nothing to tap. A test measuring a Retry button must pass
  `retry: (_, _) => null` to ProviderScope, or it measures the backoff.
- **A count in a header drifts; a count from the list does not.** I incremented
  the audit's "CLOSED (n)" by hand for a whole run and it ended 26 short of the
  truth. Same class of error as reporting a review complete from memory. Count
  the file.
- **`dart format <dir>` reformats everything it touches.** One careless run
  produced a 3,500-line diff over 50 unrelated files; the fix was `git checkout`
  on everything outside the actual change. Format the file you edited, never the
  tree.
- **A mutation that does not apply looks exactly like a test that cannot fail.**
  Sabotaging the DM thread by string replacement reported "0 failures" twice -
  not because the tests were weak, but because `dart format` had reflowed the
  call and my search strings no longer matched. Both were no-ops. ALWAYS assert
  the mutation landed (`assert old in s`) before drawing a conclusion from a
  green run; a silent no-op is the one failure mode of sabotage-proving itself.
- **Mutation-tested the whole of review #2's new SQL (2026-08-05).** Six
  mutations, six caught: dm_inbox sorted oldest-first (5 failures),
  set_match_squad made additive again (7), mark_thread_delivered stamping the
  caller's own messages (2), the leaderboard CTE unfiltered again (1), the claim
  index dropped + auth.uid() un-hoisted (3), renew_post without its status guard
  (3). Restore with `supabase db reset`, not by hand.
- **"record_ball validates it" is not an answer to "edit_ball does not".** I
  closed review-#2 finding 28 as REFUTED by checking the function I already had
  open, not the two the finding named. A refutation has to land on the SAME code
  path the finding is about; if it does not, it is a different (true) statement
  that happens to be nearby. Review #3 found it again with two independent
  lenses and it reproduced on the first try.
- **When one write path has a rule and two do not, fixing the two is the wrong
  fix.** Extract the rule so all three call it. record_ball/edit_ball/insert_ball
  drifted precisely because the Laws were copied into one of them.
