import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// End-to-end walkthrough of the slice-5 live viewer, driven against the live
/// local Supabase as the dev scorer. No mocked providers: the app boots for
/// real, signs in, and taps through Matches -> Watch -> each viewer tab.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot(name);
  }

  Future<void> settle(WidgetTester tester, Finder until, {int tries = 20}) async {
    for (var i = 0; i < tries; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (until.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('live viewer walkthrough (real app + live backend)', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // A prior run may have left an anonymous session; ensure we are the dev
    // scorer so "my matches" lists the seeded live match.
    final c = Supabase.instance.client;
    if (c.auth.currentUser == null || (c.auth.currentUser?.isAnonymous ?? false)) {
      await c.auth.signInWithPassword(
        email: 'dev@pitch.local',
        password: 'password123',
      );
    }

    // Wait for the shell, then open the Matches tab.
    await settle(tester, find.text('Matches'));
    expect(find.text('Matches'), findsWidgets, reason: 'shell tab bar should render');
    await tester.tap(find.text('Matches').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The matches list should show at least one started match with a Watch icon.
    await settle(tester, find.byIcon(Icons.visibility_outlined));
    expect(
      find.byIcon(Icons.visibility_outlined),
      findsWidgets,
      reason: 'a live match should be listed for the dev scorer (re-seed if absent)',
    );
    await shot(tester, '00_matches');

    // Open the public viewer for the newest match.
    await tester.tap(find.byIcon(Icons.visibility_outlined).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // LIVE tab: score header + batting team + segmented control.
    await settle(tester, find.text('Scorecard'));
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Scorecard'), findsWidgets);
    expect(find.textContaining('Mumbai'), findsWidgets,
        reason: 'batting team name should resolve from the live backend');
    await shot(tester, '01_live');

    // SCORECARD tab.
    await tester.tap(find.text('Scorecard'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Bowling'), findsWidgets);
    expect(find.textContaining('Extras'), findsWidgets);
    await shot(tester, '02_scorecard');

    // CHARTS tab.
    await tester.tap(find.text('Charts'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.byKey(const Key('manhattan_chart')), findsOneWidget);
    expect(find.byKey(const Key('worm_chart')), findsOneWidget);
    await shot(tester, '03_charts');

    // INFO tab.
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.textContaining('Toss'), findsWidgets);
    await shot(tester, '04_info');

    // Tear down realtime before the test tree unmounts: the viewer's live
    // `match:<id>` channel keeps a heartbeat Timer that would otherwise trip
    // the integration_test "pending timer at teardown" check.
    await c.removeAllChannels();
    c.realtime.disconnect();
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
