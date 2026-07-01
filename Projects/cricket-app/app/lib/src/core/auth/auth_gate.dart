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
    data: (row) => row == null ? AuthGate.needsProfile : AuthGate.ready,
    loading: () => AuthGate.loading,
    // AUTH-4: a transient profile-read failure must NOT dump an onboarded user
    // onto create-profile - surface a retry instead.
    error: (_, _) => AuthGate.error,
  );
});
