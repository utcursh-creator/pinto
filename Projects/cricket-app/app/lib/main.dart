import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A release build without --dart-define-from-file=hosted_defines.json points
  // at the LOCAL stack and can reach nothing - every screen fails with a
  // connection error and the app looks broken. Refuse to start rather than ship
  // a dead binary (penetration review 2026-07-07).
  SupabaseEnv.assertReleaseConfigured();
  await Supabase.initialize(
    url: SupabaseEnv.url,
    publishableKey: SupabaseEnv.publishableKey,
  );
  runApp(const ProviderScope(child: PitchApp()));
}
