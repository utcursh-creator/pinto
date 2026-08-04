import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Whole-system review #2 (2026-07-28): the console could not record ANY
/// dismissal off a wide or a no-ball.
///
/// `_wicket()` always called `_record(...)` with no wides and no no-ball, so
/// every dismissal it produced was a legal delivery. That makes a stumping off
/// a wide - a T20 staple - and a run-out off a no-ball unrecordable. The
/// scorer's only recourse is to log an ordinary run-out, which corrupts the
/// innings twice: the extra run is lost, AND a legal ball is consumed, so the
/// over ends one delivery early and every over after it is misattributed.
///
/// The Laws bind which dismissals are even possible, and record_ball already
/// enforces them (pgTAP 125). Off a wide: stumped / run out / hit wicket /
/// obstructing. Off a no-ball: run out / obstructing / hit the ball twice.
class _SpyRepo extends Fake implements MatchRepository {
  int? sawWides;
  int? sawNoBall;
  String? sawWicketType;
  int calls = 0;

  @override
  Future<({String? deliveryId, bool wagonApplicable})> recordBall({
    required String inningsId,
    required String bowlerId,
    int runsOffBat = 0,
    int wides = 0,
    int noBallPenalty = 0,
    int byes = 0,
    int legByes = 0,
    int penalty = 0,
    bool isOverthrow = false,
    String? noballSecondaryKind,
    String? wicketType,
    String? dismissedPlayerId,
    String? incomingBatterId,
    String? fielderId,
    bool? crossed,
    int? expectedLastSeq,
  }) async {
    calls++;
    sawWides = wides;
    sawNoBall = noBallPenalty;
    sawWicketType = wicketType;
    return (deliveryId: 'd1', wagonApplicable: false);
  }
}

Widget _console(_SpyRepo spy) => ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(spy),
        matchProvider.overrideWith(
            (ref, id) async => {'balls_per_over': 6, 'status': 'live'}),
        currentInningsProvider.overrideWith((ref, id) async => {
              'id': 'in1',
              'batting_team_id': 'A',
              'bowling_team_id': 'B',
              'target': null,
            }),
        matchSquadProvider.overrideWith((ref, id) async => [
              {
                'team_id': 'A', 'team_member_id': 's1',
                'team_members': {'guest_name': 'Rahul', 'profiles': null},
              },
              {
                'team_id': 'A', 'team_member_id': 's2',
                'team_members': {'guest_name': 'Arjun', 'profiles': null},
              },
              {
                'team_id': 'B', 'team_member_id': 'b1',
                'team_members': {'guest_name': 'Bumrah', 'profiles': null},
              },
            ]),
        inningsStateProvider.overrideWith((ref, id) async => {
              'runs': 42,
              'wickets': 9,
              // last wicket, so the sheet does not require an incoming batter -
              // this test is about what reaches recordBall, not the dropdown
              'wickets_remaining': 1,
              'over': '5.2',
              'striker_id': 's1',
              'non_striker_id': 's2',
              'last_seq': 33,
            }),
      ],
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );

/// The pad is absorbed until a bowler is chosen for the over.
Future<void> _pickBowler(WidgetTester tester) async {
  await tester.tap(find.text('Pick'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bumrah'));
  await tester.pumpAndSettle();
}

Future<void> _openWicketSheet(WidgetTester tester) async {
  await tester.tap(find.text('WICKET'));
  await tester.pumpAndSettle();
}

/// With a run-out selected the sheet grows past the 600pt test viewport (the
/// who-is-out chips, the runs counter and the crossed switch all appear). It
/// scrolls - verified by dragging - so scroll to the button rather than tapping
/// into empty space and silently recording nothing.
Future<void> _tapRecord(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Record wicket'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Record wicket'));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a stumping off a wide reaches recordBall as a wide '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_console(spy));
        await tester.pumpAndSettle();
        await _pickBowler(tester);
        await _openWicketSheet(tester);

        await tester.tap(find.text('Wide'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stumped'));
        await tester.pumpAndSettle();
        await _tapRecord(tester);

        expect(spy.calls, 1, reason: 'the wicket was recorded');
        expect(spy.sawWicketType, 'stumped');
        expect(spy.sawWides, 1,
            reason: 'a stumping off a wide MUST be sent as a wide - recorded '
                'as a legal ball it loses the extra run and burns a delivery, '
                'so the over ends a ball early');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a run-out off a no-ball reaches recordBall as a no-ball '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_console(spy));
        await tester.pumpAndSettle();
        await _pickBowler(tester);
        await _openWicketSheet(tester);

        await tester.tap(find.text('No-ball'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Run out'));
        await tester.pumpAndSettle();
        await _tapRecord(tester);

        expect(spy.calls, 1);
        expect(spy.sawWicketType, 'run_out');
        expect(spy.sawNoBall, 1,
            reason: 'the no-ball penalty must still be charged');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the sheet offers only dismissals the Laws allow on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_console(spy));
        await tester.pumpAndSettle();
        await _pickBowler(tester);
        await _openWicketSheet(tester);

        // legal delivery: the full set
        expect(find.text('Bowled'), findsOneWidget);
        expect(find.text('Stumped'), findsOneWidget);

        await tester.tap(find.text('Wide'));
        await tester.pumpAndSettle();
        expect(find.text('Stumped'), findsOneWidget,
            reason: 'stumped off a wide is legal');
        expect(find.text('Bowled'), findsNothing,
            reason: 'you cannot be bowled off a wide - record_ball rejects it, '
                'so offering it only produces a raw server error');
        expect(find.text('Caught'), findsNothing);

        await tester.tap(find.text('No-ball'));
        await tester.pumpAndSettle();
        expect(find.text('Run out'), findsOneWidget);
        expect(find.text('Stumped'), findsNothing,
            reason: 'you cannot be stumped off a no-ball');
        expect(find.text('LBW'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
