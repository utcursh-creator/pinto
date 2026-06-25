import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// Drives the player stats screen on the real app against live local Supabase:
/// Profile -> My cricket -> career panels. Requires the completed match seeded
/// by /tmp/seed_complete_match.py (dev = Utkarsh A.: 30* batting, 2 wkts, 1 catch).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot(name);
  }

  Future<void> settle(WidgetTester tester, Finder until, {int tries = 25}) async {
    for (var i = 0; i < tries; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (until.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('profile -> my cricket -> career stats (real app)', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final c = Supabase.instance.client;
    if (c.auth.currentUser == null || (c.auth.currentUser?.isAnonymous ?? false)) {
      await c.auth.signInWithPassword(
        email: 'dev@pitch.local',
        password: 'password123',
      );
    }

    // Go to the Profile tab and open "My cricket".
    await settle(tester, find.text('Profile'));
    await tester.tap(find.text('Profile').last);
    await settle(tester, find.text('My cricket'));
    expect(find.text('My cricket'), findsOneWidget);
    await shot(tester, '20_profile');

    await tester.tap(find.text('My cricket'));
    await settle(tester, find.byKey(const Key('stats_batting')));

    // Real seeded figures round-trip through player_public_profile.
    expect(find.text('Utkarsh A.'), findsWidgets, reason: 'identity header + title');
    expect(find.textContaining('2 matches'), findsOneWidget);
    expect(find.byKey(const Key('stats_batting')), findsOneWidget);
    expect(find.byKey(const Key('stats_bowling')), findsOneWidget);
    expect(find.byKey(const Key('stats_fielding')), findsOneWidget);
    expect(find.text('30*'), findsWidgets, reason: 'HS 30 not out');
    expect(find.text('2/2'), findsOneWidget, reason: 'BBI 2/2');
    expect(find.text('-'), findsWidgets, reason: 'batting average undefined (never out)');
    await shot(tester, '21_stats');

    // Scroll to the recent-form strip.
    await tester.scrollUntilVisible(
      find.byKey(const Key('stats_form')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('stats_form')), findsOneWidget);
    await shot(tester, '22_form');
  });
}
