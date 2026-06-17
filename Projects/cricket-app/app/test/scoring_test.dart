import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';
import 'package:pitch_app/src/features/scoring/presentation/start_match_screen.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Start match screen renders on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myTeamsProvider.overrideWith((ref) async => []),
            allTeamsProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: StartMatchScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Start a match'), findsWidgets);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Scoring console shows the live score on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchProvider.overrideWith(
              (ref, id) async => {'balls_per_over': 6},
            ),
            currentInningsProvider.overrideWith(
              (ref, id) async => {
                'id': 'in1',
                'batting_team_id': 'A',
                'bowling_team_id': 'B',
                'target': null,
              },
            ),
            matchSquadProvider.overrideWith(
              (ref, id) async => [
                {
                  'team_id': 'A',
                  'team_member_id': 's1',
                  'team_members': {'guest_name': 'Rahul', 'profiles': null},
                },
                {
                  'team_id': 'A',
                  'team_member_id': 's2',
                  'team_members': {'guest_name': 'Arjun', 'profiles': null},
                },
              ],
            ),
            inningsStateProvider.overrideWith(
              (ref, id) async => {
                'runs': 12,
                'wickets': 1,
                'over': '2.3',
                'striker_id': 's1',
                'non_striker_id': 's2',
              },
            ),
          ],
          child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('12/1'), findsOneWidget);
      expect(find.textContaining('Over 2.3'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
