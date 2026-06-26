import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// Drives the home-base flow on the real app: Discover -> Location -> set a
/// manual point -> Save, then verifies it PERSISTED via my_home_location()
/// (set_my_location was previously never called from any UI).
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

  testWidgets('set + persist home base (real app)', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final c = Supabase.instance.client;
    if (c.auth.currentUser == null || (c.auth.currentUser?.isAnonymous ?? false)) {
      await c.auth.signInWithPassword(
        email: 'dev@pitch.local',
        password: 'password123',
      );
    }

    // Discover -> Location screen (the place pin).
    await settle(tester, find.byIcon(Icons.place_outlined));
    await tester.tap(find.byIcon(Icons.place_outlined).first);
    await settle(tester, find.text('Latitude'));
    await shot(tester, '40_location');

    // Enter a distinct point (Bengaluru) and save.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '12.9716');
    await tester.enterText(fields.at(1), '77.5946');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // It must have PERSISTED server-side (the gap was: set_my_location unused).
    final home = await c.rpc('my_home_location') as List;
    expect(home, isNotEmpty, reason: 'home base should be persisted');
    final lat = ((home.first as Map)['lat'] as num).toDouble();
    expect(lat, closeTo(12.97, 0.01));
    await shot(tester, '41_after_save');
  });
}
