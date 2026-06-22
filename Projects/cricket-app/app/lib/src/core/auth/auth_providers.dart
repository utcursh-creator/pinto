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

/// True when there is no session or the session is an anonymous one. Anonymous
/// users have `is_anonymous: true` in their app metadata.
bool isAnonymousSession(Session? session) {
  if (session == null) return true;
  return session.user.appMetadata['is_anonymous'] == true;
}

/// Whether the current viewer is anonymous (or signed out). Overridable in
/// widget tests so screens can gate authed-only content without a real Session.
final isAnonymousProvider = Provider<bool>((ref) {
  return isAnonymousSession(ref.watch(currentSessionProvider));
});

/// On launch with no session, create an anonymous one so the realtime
/// WebSocket and the backend's anon read policies work for login-free viewing.
/// Tolerant: if anonymous sign-in is disabled, pure live-viewing still works
/// via the anon REST role.
final anonBootstrapProvider = FutureProvider<void>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client.auth.currentSession != null) return;
  try {
    await client.auth.signInAnonymously();
  } on AuthException catch (_) {
    // tolerated by design
  }
});
