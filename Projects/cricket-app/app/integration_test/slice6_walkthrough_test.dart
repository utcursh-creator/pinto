import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// Drives the slice-6 flows on the real app against live local Supabase:
/// the discover->match keystone bridge, and find-live -> public viewer.
/// Requires the seeded team_seeking_opponent post + a live match.
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

  testWidgets('keystone bridge + find-live (real app)', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final c = Supabase.instance.client;
    if (c.auth.currentUser == null || (c.auth.currentUser?.isAnonymous ?? false)) {
      await c.auth.signInWithPassword(
        email: 'dev@pitch.local',
        password: 'password123',
      );
    }

    // --- Keystone bridge: discover post -> propose -> pre-seeded setup ---
    await settle(tester, find.textContaining('Bandra Blasters'));
    expect(find.textContaining('Bandra Blasters'), findsWidgets,
        reason: 'seeded team_seeking_opponent post should be in the feed');
    await tester.tap(find.textContaining('Bandra Blasters need an opponent').first);
    await settle(tester, find.text('Propose a match'));
    expect(find.text('Propose a match'), findsOneWidget);
    await shot(tester, '10_post_detail');

    await tester.tap(find.text('Propose a match'));
    await settle(tester, find.text('Start a match'));
    expect(find.text('Start a match'), findsWidgets);
    // opponent pre-selected from the post's team
    expect(find.textContaining('Bandra Blasters'), findsWidgets,
        reason: 'wizard should pre-select the bridged opponent');
    await shot(tester, '11_bridge_setup');

    // --- Find live: Matches -> Watch live -> viewer ---
    await tester.tap(find.text('Matches').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.sensors).first);
    await settle(tester, find.textContaining(' v '));
    expect(find.textContaining(' v '), findsWidgets,
        reason: 'live list should show "A v B"');
    await shot(tester, '12_live_list');

    await tester.tap(find.textContaining(' v ').first);
    await settle(tester, find.text('Scorecard'));
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Scorecard'), findsWidgets);
    await shot(tester, '13_viewer_from_live');

    await c.removeAllChannels();
    c.realtime.disconnect();
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
