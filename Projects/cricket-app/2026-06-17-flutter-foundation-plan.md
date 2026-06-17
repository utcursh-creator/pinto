---
type: plan
category: frontend
project: cricket-app
date: 2026-06-17
status: draft
sub_project: 5
slice: 1
related: 2026-06-17-flutter-foundation-design.md
---

# Flutter App Foundation - build plan (sub-project 5, slice 1)

Green bar for every task: `flutter analyze` clean AND `flutter test` passing. App at `Projects/cricket-app/app/`. Pinned versions per the verified recipe (intentional major skew - do not align).

## T1 - Toolchain ready
- Install Flutter (stable) + Android (Android Studio or cmdline-tools + SDK), accept Android licenses (`yes | flutter doctor --android-licenses`).
- `flutter doctor -v` green for: Flutter, Xcode (iOS), Android toolchain, a connected device/emulator. CocoaPods present (`sudo gem install cocoapods` if missing).
- Done = `flutter doctor` shows no blocking [✗] for iOS + Android.

## T2 - Scaffold
- `flutter create --org dev.pitch --project-name pitch_app .` inside `Projects/cricket-app/app/` (or create then move). Both iOS + Android platforms.
- Bump iOS deployment target to 16.0 (ios/Podfile `platform :ios, '16.0'` + Runner project). `cd ios && pod install` succeeds.
- Verify the default app: `flutter analyze` clean, `flutter test` (default widget test) passes, `flutter build ios --no-codesign --debug` and `flutter build apk --debug` both compile.
- Commit the clean scaffold.

## T3 - Dependencies + lints
- pubspec dependencies: `flutter_riverpod: 3.3.2`, `go_router: 17.3.0`, `supabase_flutter: 2.15.0`. dev_dependencies: `flutter_lints: 6.0.0`, `riverpod_lint: 3.1.4`. (No build_runner/riverpod_generator/custom_lint/hooks/annotation.)
- analysis_options.yaml: `include: package:flutter_lints/flutter.yaml` + top-level `plugins:\n  riverpod_lint: ^3.1.4` (NOT analyzer.plugins.custom_lint).
- `flutter pub get` clean; `flutter analyze` clean.

## T4 - Supabase init + config
- `lib/src/core/config/env.dart`: `SupabaseEnv` reads `--dart-define SUPABASE_URL / SUPABASE_ANON_KEY`; local defaults `http://127.0.0.1:54321` + the local anon JWT (from `supabase status`).
- `lib/src/core/supabase/supabase_providers.dart`: `supabaseClientProvider`.
- `main.dart`: `WidgetsFlutterBinding.ensureInitialized()` -> `await Supabase.initialize(url, anonKey)` -> `runApp(ProviderScope(child: PitchApp()))`.
- Flip `supabase/config.toml` `enable_anonymous_sign_ins = true`; `supabase stop && supabase start` (or db reset). (Backend repo change - separate small commit.)
- Done = app boots to a blank MaterialApp against the local stack.

## T5 - Auth providers + anon bootstrap
- `core/auth/auth_providers.dart`: `authStateChangesProvider = StreamProvider((ref)=>client.auth.onAuthStateChange)`; `currentSessionProvider`; an anon-bootstrap (on launch, if `currentSession == null` try `signInAnonymously()`, tolerate AuthException).
- `core/auth/profile_provider.dart`: `myProfileProvider` (FutureProvider/AsyncNotifier) selecting the caller's `profiles` row (null => not onboarded). Runs only with a real (non-anon) session.

## T6 - Theme
- `core/theme/brand_tokens.dart`: teal `#0F6E56`, flair colors (amber/gray/blue), type scale.
- `core/theme/app_theme.dart`: `AppTheme.material()` (M3, `useMaterial3:true`, ColorScheme.fromSeed teal) and `AppTheme.cupertino()` (CupertinoThemeData-tuned ThemeData). App picks per platform.

## T7 - Platform-adaptive layer
- `core/platform/platform.dart`: `isCupertino(context)`; adaptive helpers.
- `core/platform/adaptive_scaffold.dart`: `AdaptiveScaffold`/`AdaptiveAppBar` (Material AppBar vs CupertinoNavigationBar), using `.adaptive()` controls.

## T8 - Routing + onboarding gate
- `core/routing/routes.dart`: path constants (`/splash`, `/sign-in`, `/onboarding/create-profile`, `/discover`, `/matches`, `/profile`).
- `core/routing/go_router_refresh.dart`: `GoRouterRefreshStream` over `auth.onAuthStateChange`.
- `core/routing/app_router.dart`: `goRouterProvider` -> GoRouter(initialLocation `/splash`, refreshListenable, redirect gate using `currentSession` + `myProfileProvider.valueOrNull`), with `StatefulShellRoute.indexedStack` (3 branches, per-branch GlobalKeys) + the sign-in / create-profile / splash routes.

## T9 - Shell + screens (placeholders + dev-auth)
- `features/shell/presentation/adaptive_tab_shell.dart`: iOS `Scaffold(body: navigationShell, bottomNavigationBar: CupertinoTabBar)`, Android `Scaffold(... NavigationBar)`; `goBranch` wiring. (NOT CupertinoTabScaffold.)
- `features/auth/presentation/sign_in_screen.dart`: kDebugMode email+password against local stack + stubbed Google/Apple buttons.
- `features/onboarding/presentation/create_profile_screen.dart`: minimal display-name form -> insert profiles row.
- `features/{discover,matches,profile}/presentation/*_screen.dart`: branded placeholders.

## T10 - Tests + run
- `test/app_smoke_test.dart`: override auth+profile providers to signed-in-with-profile; pump; assert the 3-tab shell renders.
- `test/onboarding_redirect_test.dart`: no-profile state asserts redirect to create-profile.
- `test/platform_adaptive_test.dart`: `debugDefaultTargetPlatformOverride` iOS vs Android -> CupertinoTabBar vs NavigationBar.
- `flutter analyze` clean; `flutter test` green. Manual: `flutter run` on an iOS simulator AND an Android emulator -> dev-auth sign-in -> Discover placeholder; confirm an anon session is created cold.
- Commit the foundation.

## Risks (from the recipe, pre-empt)
- iOS 16.0 bump is the #1 build break (pod install) - do it in T2.
- Anon sign-in disabled in config.toml - flip in T4 or signInAnonymously() throws at runtime (not a build error).
- go_router v17 + StatefulShellRoute: use the v17 redirect/shell signatures, not older blog snippets.
- AsyncValue-in-redirect timing: guard with valueOrNull + /splash so the gate doesn't prematurely bounce.
- Private realtime channel join needs a session; for pure logged-out viewing confirm the anon REST role authorizes the private `match:%` join, else setAuth + resubscribe (later slice concern).

## Definition of done
- `flutter doctor` green (iOS + Android), `flutter analyze` clean, `flutter test` green (3 tests).
- App runs on iOS sim + Android emulator: dev-auth login -> 3-tab adaptive shell (Cupertino chrome on iOS, M3 on Android) with branded placeholders; onboarding gate routes a profile-less user to create-profile; cold launch creates an anon session.
- Foundation committed; ready for slice 2 (Identity UI).
