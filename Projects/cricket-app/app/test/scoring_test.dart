import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';
import 'package:pitch_app/src/features/scoring/presentation/start_match_screen.dart';

/// The console writes the innings-break status (SCOR-1) as soon as the break
/// panel shows - the widget test needs that write to land somewhere harmless.
class _FakeMatchRepository extends Fake implements MatchRepository {
  @override
  Future<void> markInningsBreak(String matchId) async {}
}

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

    testWidgets('1st innings end shows the innings break + chase target on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchRepositoryProvider.overrideWithValue(_FakeMatchRepository()),
            matchProvider.overrideWith(
              (ref, id) async => {'balls_per_over': 6, 'status': 'live'},
            ),
            currentInningsProvider.overrideWith(
              (ref, id) async => {
                'id': 'in1',
                'batting_team_id': 'A',
                'bowling_team_id': 'B',
                'target': null,
              },
            ),
            matchSquadProvider.overrideWith((ref, id) async => []),
            matchTeamNamesProvider.overrideWith(
              (ref, id) async => {'A': 'Mumbai', 'B': 'Chennai'},
            ),
            inningsStateProvider.overrideWith(
              (ref, id) async => {
                'runs': 154,
                'wickets': 6,
                'over': '20.0',
                'innings_status': 'completed',
              },
            ),
          ],
          child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Innings break'), findsOneWidget);
      expect(find.textContaining('Mumbai finished on 154/6'), findsOneWidget);
      expect(find.textContaining('Target: 155'), findsOneWidget);
      expect(find.text('Start 2nd innings'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('2nd innings end shows the computed result + finish on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchProvider.overrideWith(
              (ref, id) async => {'balls_per_over': 6, 'status': 'live'},
            ),
            currentInningsProvider.overrideWith(
              (ref, id) async => {
                'id': 'in2',
                'batting_team_id': 'B',
                'bowling_team_id': 'A',
                'target': 155,
              },
            ),
            matchSquadProvider.overrideWith((ref, id) async => []),
            matchTeamNamesProvider.overrideWith(
              (ref, id) async => {'A': 'Mumbai', 'B': 'Chennai'},
            ),
            inningsStateProvider.overrideWith(
              (ref, id) async => {
                'runs': 155,
                'wickets': 4,
                'over': '19.3',
                'innings_status': 'completed',
                'result': {
                  'result_type': 'win_by_wickets',
                  'winner_team_id': 'B',
                  'margin_wickets': 6,
                  'balls_remaining': 3,
                },
              },
            ),
          ],
          child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Match over'), findsOneWidget);
      expect(find.textContaining('Chennai won by 6 wickets'), findsOneWidget);
      expect(find.text('Finish match & view scorecard'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
