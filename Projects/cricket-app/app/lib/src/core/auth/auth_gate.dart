import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import 'profile_provider.dart';

/// The single onboarding-gate state, derived from session + profile. The router
/// switches on this; tests override it directly (no Session/client mocking).
enum AuthGate { loading, anonymous, needsProfile, ready, error }

final authGateProvider = Provider<AuthGate>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (isAnonymousSession(session)) return AuthGate.anonymous;
  final profile = ref.watch(myProfileProvider);
  return profile.when(
    // CRITICAL (re-review 2026-07-07): `when()` defaults skipLoadingOnReload to
    // FALSE, so a provider that rebuilds because a WATCHED DEPENDENCY changed
    // reports loading even though it is still holding a perfectly good value.
    //
    // supabase_flutter auto-refreshes the JWT about an hour in (and on every
    // resume from background); gotrue's Session == compares the tokens, so
    // currentSessionProvider yields a NEW session, myProfileProvider reloads,
    // and this gate flipped ready -> loading. The router listens to the gate,
    // re-runs its redirect, and the loading branch sends every non-public
    // location to /splash - a top-level route OUTSIDE the tab shell, so the
    // shell and every branch navigator were torn down. A scorer half way
    // through an innings was dumped on Discover having touched nothing.
    //
    // A reload is not a cold start: keep answering with what we already know.
    // The FIRST load has no previous value, so it still reports loading and the
    // splash gate still works.
    skipLoadingOnReload: true,
    // HIGH (review #2, finding 11): the ERROR branch was the other half of the
    // same bug. skipError also defaults to FALSE, so a re-read that failed -
    // the JWT refresh at a ground with bad signal, or Edit profile's invalidate
    // on save - reported error even though the gate was still holding a
    // perfectly good profile. The router's error branch shares the loading
    // branch's `return loc == Routes.splash ? null : Routes.splash`, so the
    // whole stack was replaced with a top-level route outside the tab shell:
    // console gone, half-entered wicket dialog gone, and Retry lands on
    // Discover rather than back in the match.
    //
    // `skipError` only applies when a previous value EXISTS (riverpod 3.3.2:
    // `hasError && (!hasValue || !skipError)`), so a first read that fails still
    // reports error and still holds on the splash with a retry - which is right,
    // because there we genuinely do not know whether this user has onboarded.
    skipError: true,
    data: (row) => row == null ? AuthGate.needsProfile : AuthGate.ready,
    loading: () => AuthGate.loading,
    // AUTH-4: a transient profile-read failure must NOT dump an onboarded user
    // onto create-profile - surface a retry instead.
    error: (_, _) => AuthGate.error,
  );
});
