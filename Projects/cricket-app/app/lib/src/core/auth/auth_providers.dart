import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';

/// Streams Supabase auth changes (sign-in/out, token refresh, anon promotion).
final authStateChangesProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

/// The current session, re-read on every auth event.
final currentSessionProvider = Provider<Session?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(supabaseClientProvider).auth.currentSession;
});

/// True when there is no session or the session is an anonymous one. Supabase
/// exposes anonymity as the TOP-LEVEL `is_anonymous` claim (parsed onto
/// `User.isAnonymous`); it is NOT in `app_metadata` (that stays `{}` for anon
/// users), so reading `appMetadata['is_anonymous']` wrongly classified every
/// anonymous user as a real one and forced them to the create-profile gate.
bool isAnonymousSession(Session? session) {
  if (session == null) return true;
  return session.user.isAnonymous;
}

/// Whether the current viewer is anonymous (or signed out). Overridable in
/// widget tests so screens can gate authed-only content without a real Session.
final isAnonymousProvider = Provider<bool>((ref) {
  return isAnonymousSession(ref.watch(currentSessionProvider));
});

/// On launch with no session, create an anonymous one so the realtime
/// WebSocket and the backend's anon read policies work for login-free viewing.
/// Also re-creates an anonymous session after sign-out (AUTH-2) so viewing +
/// realtime keep working instead of silently breaking until an app relaunch.
/// Tolerant: if anonymous sign-in is disabled, pure live-viewing still works
/// via the anon REST role.
final anonBootstrapProvider = FutureProvider<void>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  Future<void> ensureAnon() async {
    if (client.auth.currentSession != null) return;
    try {
      await client.auth.signInAnonymously();
    } on AuthException catch (_) {
      // tolerated by design
    }
  }

  // AUTH-2: whenever we drop to no session (sign-out), restore an anon one.
  ref.listen(authStateChangesProvider, (_, next) {
    if (next.value?.event == AuthChangeEvent.signedOut &&
        client.auth.currentSession == null) {
      ensureAnon();
    }
  });

  if (client.auth.currentSession != null) return;
  try {
    await client.auth.signInAnonymously();
  } on AuthException catch (_) {
    // tolerated by design
  }
});
