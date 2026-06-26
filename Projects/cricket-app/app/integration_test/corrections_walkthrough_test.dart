import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// Drives the scoring corrections flow on the real app against live local
/// Supabase: Matches -> live match -> console -> ball log -> edit a ball.
/// Requires the seeded live match (dev is the scorer, 11 balls bowled).
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

  testWidgets('scorer can edit a past ball (real app)', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final c = Supabase.instance.client;
    if (c.auth.currentUser == null || (c.auth.currentUser?.isAnonymous ?? false)) {
      await c.auth.signInWithPassword(
        email: 'dev@pitch.local',
        password: 'password123',
      );
    }

    // Matches tab -> open the LIVE match (its subtitle reads "live") -> console.
    // (Completed matches sort first and would open the read-only viewer.)
    await settle(tester, find.text('Matches'));
    await tester.tap(find.text('Matches').last);
    await settle(tester, find.textContaining('live'));
    await tester.tap(find.textContaining('live').first);
    await settle(tester, find.byTooltip('Ball log / corrections'));
    await shot(tester, '30_console');

    // Open the ball log (corrections).
    await tester.tap(find.byTooltip('Ball log / corrections'));
    await settle(tester, find.text('Ball log'));
    expect(find.textContaining('Tap a ball to edit'), findsOneWidget);
    // real deliveries render (bowler -> striker subtitle)
    expect(find.textContaining('  to  '), findsWidgets);
    await shot(tester, '31_ball_log');

    // Edit the first ball -> 6 runs off the bat.
    await tester.tap(find.textContaining('  to  ').first);
    await settle(tester, find.text('Edit this ball'));
    await tester.tap(find.text('Edit this ball'));
    await settle(tester, find.text('Edit ball'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Runs'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '6'));
    await tester.pumpAndSettle();
    await shot(tester, '32_editor');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester, find.text('6'));

    // the edited ball now reads as a 6 in the log
    expect(find.text('6'), findsWidgets);
    await shot(tester, '33_after_edit');
  });
}
