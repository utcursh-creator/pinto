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
  // Read our own row via the my_profile() RPC, not a direct `select *`: after
  // SEC-1, `phone` is column-denied on the table (a bare select would fail),
  // and the owner's phone lives only behind this SECURITY DEFINER function.
  final row = await client.rpc('my_profile');
  return row == null ? null : Map<String, dynamic>.from(row as Map);
});
