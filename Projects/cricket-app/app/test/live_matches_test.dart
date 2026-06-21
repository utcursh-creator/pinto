import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/live_matches_screen.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Watch live lists in-progress matches on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              liveMatchesProvider.overrideWith(
                (ref) async => [
                  {
                    'id': 'm1',
                    'status': 'live',
                    'venue': 'Shivaji Park',
                    'overs_limit': 20,
                    'team_a': {'name': 'Mumbai United'},
                    'team_b': {'name': 'Dadar CC'},
                  },
                ],
              ),
            ],
            child: const MaterialApp(home: LiveMatchesScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Mumbai United v Dadar CC'), findsOneWidget);
        expect(find.textContaining('live'), findsWidgets);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Watch live shows an empty state on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [liveMatchesProvider.overrideWith((ref) async => [])],
            child: const MaterialApp(home: LiveMatchesScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('No live matches right now.'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
