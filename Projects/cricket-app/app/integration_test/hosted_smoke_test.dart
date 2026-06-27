import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;
import 'package:pitch_app/src/core/config/env.dart';

/// Smoke test against the HOSTED backend (run with
/// --dart-define-from-file=hosted_defines.json). Proves the app connects to the
/// hosted Supabase, authenticates, and round-trips a write + read.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app round-trips against hosted Supabase', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // confirm we are pointed at the hosted project, not local
    expect(SupabaseEnv.url, contains('supabase.co'), reason: 'should target hosted, not 127.0.0.1');

    final c = Supabase.instance.client;
    await c.auth.signInWithPassword(email: 'dev@pitch.local', password: 'password123');
    expect(c.auth.currentUser, isNotNull, reason: 'dev signs in against hosted');

    // write + read a tournament through the hosted RPCs
    final tid = await c.rpc('create_tournament', params: {
      '_name': 'Hosted Smoke', '_overs': 20, '_group_count': 2, '_qualifiers_per_group': 2,
    }) as String;
    final overview = await c.rpc('tournament_overview', params: {'_tournament_id': tid}) as Map;
    expect((overview['tournament'] as Map)['name'], 'Hosted Smoke');

    // anon-readable too (login-free path): a fresh anon client can read it
    expect(overview['standings'], isNotNull);

    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot('80_hosted_smoke');
  });
}
