import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/app.dart';
import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/presentation/discover_screen.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';

void main() {
  testWidgets('a ready user lands on the 3-tab shell (Discover branch)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authGateProvider.overrideWithValue(AuthGate.ready),
          anonBootstrapProvider.overrideWith((ref) async {}),
          isAnonymousProvider.overrideWithValue(false),
        ],
        child: const PitchApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DiscoverScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget); // Android default
    expect(find.text('Matches'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('tapping the Matches tab switches branches', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authGateProvider.overrideWithValue(AuthGate.ready),
          anonBootstrapProvider.overrideWith((ref) async {}),
          isAnonymousProvider.overrideWithValue(false),
          myMatchesProvider.overrideWith((ref) async => []),
          currentSessionProvider.overrideWithValue(null),
        ],
        child: const PitchApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Matches'));
    await tester.pumpAndSettle();

    expect(find.text('No matches yet. Start one.'), findsOneWidget);
  });
}
