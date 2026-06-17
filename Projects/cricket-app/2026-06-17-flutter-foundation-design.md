---
type: design
category: frontend
project: cricket-app
date: 2026-06-17
status: draft
sub_project: 5
slice: 1
---

# Flutter App Foundation (sub-project 5, slice 1)

## Context

Three backends are live + tested (244 pgTAP). The full app is wireframed in two platform languages (iOS HIG + Material 3, ~50 panels each). This sub-project is the FIRST of 5 frontend slices: the App Foundation that every later slice builds on. It does NOT build feature screens - it builds the skeleton, wiring, theming, navigation, and a dev-auth path so subsequent slices drop screens into a working shell.

Frontend slices (build order): **1) App Foundation (this doc)** -> 2) Identity UI -> 3) Discover/Matchmaking UI (the headline) -> 4) Match Setup + Scoring UI -> 5) Live Viewer UI.

## Locked decisions (from prior sessions)

- **Flutter** (Dart) for one codebase, two platform looks.
- **Riverpod** for state management (2026 industry standard; fits subscribe-to-backend + push-mutations).
- **go_router** for declarative, deep-link-capable routing.
- **supabase_flutter** as the backend client (auth, Postgres/RPC, realtime, storage).
- **Platform-adaptive UI**: iOS renders Cupertino-flavored (HIG), Android renders Material 3, same Riverpod state underneath. One brand teal accent (#0F6E56) on both.
- Build against the LOCAL Supabase stack first, with a dev-auth shim (local email/password or magic link) so screens can be built before real Google/Apple OAuth + hosting.

## Scope of THIS slice (foundation only)

1. **Project scaffold**: `flutter create` app at `Projects/cricket-app/app/`, org id, both iOS + Android targets, null-safe, linted (`flutter_lints`/`very_good_analysis`).
2. **Dependency wiring**: pin verified-current versions of supabase_flutter, flutter_riverpod (or hooks_riverpod + riverpod_annotation), go_router, plus dev deps (build_runner, riverpod_generator, custom_lint, riverpod_lint), fl_chart deferred to the charts slice.
3. **Supabase init**: a `SupabaseConfig` reading `--dart-define` (URL + anon key) so local vs hosted is a build-time flag, never hardcoded. Local defaults to `http://127.0.0.1:54321` + the local anon key. App boots `Supabase.initialize` before `runApp`.
4. **Anonymous session bootstrap**: on launch with no session, call `signInAnonymously()` so the realtime WebSocket (and the anon read policies from sub-project 4) work for login-free viewing. Promote to a real account on sign-in.
5. **Auth state**: a Riverpod `authStateProvider` streaming `onAuthStateChange`; a `profileProvider` that resolves the caller's profile row (drives the onboarding gate: no profile -> Create Profile).
6. **Routing**: go_router with a `redirect` implementing the onboarding gate (splash -> [signed out? sign in] -> [no profile? create profile] -> shell), and the 3-tab shell (Discover / Matches / Profile) as a `StatefulShellRoute`. Placeholder screens per tab.
7. **Platform-adaptive theming**: a `PlatformWidgets` layer that picks Cupertino vs Material per `Theme.of(context).platform` (overridable for testing). Define the shared brand tokens (teal, flair colors, type scale) once; expose `AppTheme.material()` and `AppTheme.cupertino()`. The 3-tab shell uses `CupertinoTabScaffold` on iOS and `NavigationBar` (M3) on Android.
8. **Dev-auth shim**: a debug-only sign-in screen (email+password against the local stack, or a "continue as test user" button) behind a `kDebugMode`/dart-define guard so foundation + later slices are buildable before OAuth is configured. Real Google/Apple buttons are stubbed (visible, wired in a later slice).
9. **Folder structure**: feature-first (`lib/src/features/<feature>/`), with `core/` for config, theme, routing, supabase client, platform adaptation. Riverpod providers colocated with features.
10. **Smoke test + analyze**: one widget test that pumps the app and asserts the shell renders; `flutter analyze` clean; both are the slice's green bar.

## Out of scope (later slices / later)

- Any real feature screen content (Discover feed, scorer console, etc.) beyond tab placeholders.
- Google / Apple OAuth provider configuration + hosted Supabase (deferred; dev-auth shim stands in).
- Push notifications, deep-link domain setup, app icons/splash branding, store metadata.
- fl_chart wiring (charts slice).
- Offline/caching (online-required, per the locked architecture).

## Open questions for the verification workflow to resolve (do not trust memory)

- Current stable versions of: flutter SDK channel, supabase_flutter, flutter_riverpod vs hooks_riverpod + riverpod_annotation/generator, go_router, flutter_lints/very_good_analysis. Pin exact recent versions.
- Riverpod 2026 idiom: code-gen (`@riverpod`) vs manual providers - which is the current recommended default?
- Best current pattern for platform-adaptive theming in Flutter (flutter_platform_widgets package vs hand-rolled adaptive layer) - is the package maintained + recommended in 2026, or is hand-rolling cleaner?
- supabase_flutter anonymous sign-in API surface + how to wire `onAuthStateChange` into a Riverpod stream provider; correct local-dev init.
- go_router + Riverpod redirect pattern (refreshListenable / a provider-driven redirect) current best practice.
- Whether `flutter create` defaults already include sound null safety + the right Gradle/iOS deployment targets in the current SDK.

## Test / verification plan

- `flutter analyze` clean (lints pass).
- `flutter test` green: a widget test that overrides the auth + profile providers to a signed-in-with-profile state and asserts the 3-tab shell + each placeholder renders; a second that asserts the onboarding redirect (no profile -> Create Profile route).
- Manual: `flutter run` against the local Supabase stack, dev-auth sign-in, land on the Discover placeholder, confirm an anonymous session is created on cold launch.
- The platform-adaptive layer tested by pumping with `debugDefaultTargetPlatformOverride` = iOS and Android and asserting the Cupertino vs Material shell.

## Verification outcome (recipe applied, wf_72889629-4e8, web-grounded)

Pinned versions (intentional major skew - do NOT align): `flutter_riverpod 3.3.2`, `go_router 17.3.0`, `supabase_flutter 2.15.0`, `flutter_lints 6.0.0`, `riverpod_lint 3.1.4` (lint only). codegen quartet (`riverpod_annotation 4.0.3` / `riverpod_generator 4.0.4` / `build_runner 2.15.0`) is NOT used this slice.

Corrections to the items above:
- **No Riverpod codegen** this slice (riverpod.dev recommends `@riverpod` only if the project already uses codegen; macros were cancelled). Use the modern MANUAL API: `Notifier`/`AsyncNotifier` + `StreamProvider`/`FutureProvider`/`Provider` with the unified `Ref`. `authStateProvider` is a plain `StreamProvider<AuthState>`, not a StateNotifier. Drop `build_runner`/`riverpod_generator` from pubspec.
- **Never use** `StateProvider`/`StateNotifier` (legacy import in Riverpod 3.x).
- **Platform-adaptive = hand-rolled.** `flutter_platform_widgets` is DISCONTINUED on pub.dev; do not use it or its forks. Switch on `Theme.of(context).platform == TargetPlatform.iOS` (not `dart:io`), use `.adaptive()` constructors, and a manual switch for structural chrome.
- **One `MaterialApp.router` for both platforms** (Cupertino widgets render inside it). Supply `AppTheme.cupertino()` ThemeData on iOS, `AppTheme.material()` on Android.
- **Tab shell**: ONE `StatefulShellRoute.indexedStack`; on iOS render `Scaffold(body: shell, bottomNavigationBar: CupertinoTabBar(...))`, on Android `Scaffold(... NavigationBar(...))`. Do NOT put `CupertinoTabScaffold` inside the StatefulShellRoute (open Flutter bugs #137833/#164300/#113757). This supersedes item 7.
- **riverpod_lint 3.x** is wired via a top-level `plugins:` block in analysis_options.yaml, NOT `analyzer: plugins: custom_lint`. Drop `custom_lint`.
- **BLOCKER (local config)**: `supabase/config.toml` has `enable_anonymous_sign_ins = false`. Flip to `true` + restart the stack, else `signInAnonymously()` throws. The dev-auth email/pw shim and pure logged-out live-viewing work regardless.
- **iOS deployment target 16.0**: supabase_flutter 2.15.0 bundles a passkeys plugin forcing iOS 16.0 (Podfile `platform :ios, '16.0'`), else `pod install` fails. Android minSdk 21 is fine.
- Use `anonKey:` (the local CLI's anon JWT) in `Supabase.initialize`, not `publishableKey`.
- Redirect-timing: guard the onboarding gate with `myProfileProvider.valueOrNull` + a `/splash` route so it does not bounce to create-profile before the profile fetch resolves.

## Prerequisite

Flutter + Android toolchain being installed (user approved "Flutter + Android too"). Xcode is present for iOS. Build/verify proceeds once `flutter doctor` is green.
