import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';
import 'auth_providers.dart';

/// The caller's own `profiles` row, or null if they have not onboarded yet.
/// Only meaningful for a real (non-anonymous) session; an anonymous session
/// has no profile row, which correctly drives the onboarding gate.
final myProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null || isAnonymousSession(session)) return null;
  final client = ref.watch(supabaseClientProvider);
  return client
      .from('profiles')
      .select()
      .eq('id', session.user.id)
      .maybeSingle();
});
