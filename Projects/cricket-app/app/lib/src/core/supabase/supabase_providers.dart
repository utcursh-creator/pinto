import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The initialized Supabase client (set up in main() before runApp).
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// The client, or null when Supabase has not been initialised.
///
/// Everything that NEEDS a backend should watch [supabaseClientProvider] and
/// fail loudly. This is for the few things that are pure optimisations - a
/// realtime channel for badge freshness - where "no client, no channel" is the
/// correct answer rather than a crash, and where demanding one would force every
/// widget test that mounts the app shell to stand up a Supabase it never calls.
final supabaseClientOrNullProvider = Provider<SupabaseClient?>((ref) {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
});
