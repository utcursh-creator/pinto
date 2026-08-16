import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/profile/presentation/settings_screen.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('settings offers account mgmt + legal + delete on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [currentSessionProvider.overrideWithValue(null)],
            child: const MaterialApp(home: SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // PROF-2: real account-management rows
        expect(find.text('Reset password'), findsOneWidget);
        expect(find.text('Change email'), findsOneWidget);
        // store compliance: legal pointers + about + DELETE (MISS-4)
        expect(find.text('Privacy policy'), findsOneWidget);
        expect(find.text('Terms of service'), findsOneWidget);
        // The screen grew a Scoring section (2026-08-05), so the version row
        // is now below the fold. The assertion is unchanged - it still has to
        // be THERE - only how the test reaches it.
        await tester.scrollUntilVisible(
            find.textContaining('Pitch v'), 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(find.textContaining('Pitch v'), findsOneWidget);
        final del = find.widgetWithText(OutlinedButton, 'Delete account');
        await tester.scrollUntilVisible(del, 200,
            scrollable: find.byType(Scrollable).first);
        expect(del, findsOneWidget);
        // the delete flow always confirms first
        await tester.tap(del);
        await tester.pumpAndSettle();
        expect(find.text('Delete your account?'), findsOneWidget);
        expect(find.text('Delete forever'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
