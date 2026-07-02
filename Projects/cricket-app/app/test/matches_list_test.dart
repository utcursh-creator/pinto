import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/matches/presentation/matches_screen.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Matches list shows A v B, the result and a Completed section '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSessionProvider.overrideWithValue(null),
            myMatchesProvider.overrideWith(
              (ref) async => [
                {
                  'id': 'm1',
                  'status': 'complete',
                  'overs_limit': 20,
                  'owner_id': 'u1',
                  'team_a': {'name': 'Mumbai'},
                  'team_b': {'name': 'Chennai'},
                  'result': {
                    'result_type': 'win_by_runs',
                    'note': 'Chennai won by 12 runs',
                  },
                },
                {
                  'id': 'm2',
                  'status': 'live',
                  'overs_limit': 10,
                  'owner_id': 'u1',
                  'team_a': {'name': 'Delhi'},
                  'team_b': {'name': 'Pune'},
                  'result': null,
                },
              ],
            ),
          ],
          child: const MaterialApp(home: MatchesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Real team names, never "Team A/Team B".
      expect(find.text('Mumbai  v  Chennai'), findsOneWidget);
      expect(find.text('Delhi  v  Pune'), findsOneWidget);
      // Section headers split live vs completed.
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      // The stored result note surfaces in the list.
      expect(find.textContaining('Chennai won by 12 runs'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
