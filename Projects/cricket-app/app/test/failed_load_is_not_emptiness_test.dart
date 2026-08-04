import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/ball_log_screen.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Whole-system review #2 (2026-07-28): a failed load is rendered as "you have
/// not set this up yet".
///
/// Both screens gate only on `isLoading`. An errored provider is NOT loading
/// and has a null value, so it falls straight through to the no-data branch:
///
///   console  -> "No innings yet. Finish setup first."
///   ball log -> "No innings to correct yet."
///
/// A scorer whose connection blipped mid-over is told their match does not
/// exist, and the obvious response - go back and run setup again - creates a
/// SECOND innings on a live match. There is no retry and no hint that anything
/// failed.
///
/// Note the inner `inningsStateProvider` already has a proper retryable error
/// branch. That is the trap: the instance was fixed, the class was not.
class _Boom implements Exception {
  @override
  String toString() => 'Exception: boom';
}

Widget _wrap(Widget child, {required bool inningsFails}) => ProviderScope(
      overrides: [
        matchProvider.overrideWith(
            (ref, id) async => {'balls_per_over': 6, 'status': 'live'}),
        currentInningsProvider.overrideWith((ref, id) async {
          if (inningsFails) throw _Boom();
          return {
            'id': 'in1',
            'batting_team_id': 'A',
            'bowling_team_id': 'B',
            'target': null,
          };
        }),
        matchSquadProvider.overrideWith((ref, id) async => []),
        inningsStateProvider.overrideWith((ref, id) async => {
              'runs': 0, 'wickets': 0, 'over': '0.0', 'legal_balls': 0,
              'wickets_remaining': 10, 'last_seq': 0,
            }),
        inningsDeliveriesProvider.overrideWith((ref, id) async => []),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('console: a failed innings load is not "finish setup first" '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_wrap(
            const ScoringConsoleScreen(matchId: 'm1'),
            inningsFails: true));
        await tester.pumpAndSettle();

        expect(find.textContaining('Finish setup first'), findsNothing,
            reason: 'telling a scorer mid-match that their innings does not '
                'exist invites them to run setup again and create a second '
                'innings on a live match');
        expect(find.textContaining('Try again'), findsOneWidget,
            reason: 'a failed load must offer a way back');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('ball log: a failed innings load is not "nothing to correct" '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
            _wrap(const BallLogScreen(matchId: 'm1'), inningsFails: true));
        await tester.pumpAndSettle();

        expect(find.textContaining('No innings to correct yet'), findsNothing,
            reason: 'the balls are there - the app just could not read them');
        expect(find.textContaining('Try again'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a genuinely unstarted match still says so '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // A match with no innings is a REAL state, and the console must still
        // send the scorer to setup. Without this the fix could be "call every
        // empty state an error", which would strand anyone starting a match.
        await tester.pumpWidget(ProviderScope(
          overrides: [
            matchProvider.overrideWith(
                (ref, id) async => {'balls_per_over': 6, 'status': 'setup'}),
            currentInningsProvider.overrideWith((ref, id) async => null),
            matchSquadProvider.overrideWith((ref, id) async => []),
          ],
          child: const MaterialApp(
              home: ScoringConsoleScreen(matchId: 'm1')),
        ));
        await tester.pumpAndSettle();

        expect(find.textContaining('Finish setup first'), findsOneWidget,
            reason: 'no innings really does mean go and set the match up');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
