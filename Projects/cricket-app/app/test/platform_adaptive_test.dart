import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/app.dart';
import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';

void main() {
  testWidgets('iOS renders a CupertinoTabBar, not a NavigationBar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authGateProvider.overrideWithValue(AuthGate.ready),
          anonBootstrapProvider.overrideWith((ref) async {}),
        ],
        child: const PitchApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Android renders a Material NavigationBar, not a CupertinoTabBar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authGateProvider.overrideWithValue(AuthGate.ready),
            anonBootstrapProvider.overrideWith((ref) async {}),
          ],
          child: const PitchApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(CupertinoTabBar), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    },
  );
}
