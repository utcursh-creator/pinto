import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/ball_log_screen.dart';

/// Journey map C4: changing a delivery's KIND after the fact.
///
/// CricHeroes lets a scorer "adjust the delivery type if a ball was incorrectly
/// marked (e.g. wide, no-ball, dot)". It is the most common correction there
/// is: the umpire's arm goes out a beat after you have already tapped 0.
///
/// The editor HAS a Delivery chip row (Legal / Wide / No-ball) and always has.
/// What was never tested is whether choosing one actually REACHES the RPC.
/// ball_log_test asserts the chip EXISTS - `expect(find.widgetWithText(
/// ChoiceChip, 'Wide'), findsOneWidget)` - and never taps it.
///
/// That is exactly the shape of the `params['_crossed']` hole found earlier
/// today: a control present on screen, a repository that accepts the argument,
/// and nothing proving the value travels between them. So this is a
/// verification, not a fix - C4 needed a test, not code.
const _matchId = 'm1';
const _inningsId = 'in1';

class _SpyRepo extends Fake implements MatchRepository {
  int? sawWides;
  int? sawRuns;
  var editCalls = 0;

  @override
  Future<void> editBall({
    required String deliveryId,
    int runsOffBat = 0,
    int wides = 0,
    int noBallPenalty = 0,
    int byes = 0,
    int legByes = 0,
    int penalty = 0,
    String? noballSecondaryKind,
    String? wicketType,
    String? dismissedPlayerId,
    String? incomingBatterId,
    String? fielderId,
    bool? crossed,
    bool clearWicket = false,
    bool clearWagon = false,
  }) async {
    editCalls++;
    sawWides = wides;
    sawRuns = runsOffBat;
  }
}

/// ONE plain dot ball - the thing a scorer taps before the umpire signals.
List<Map<String, dynamic>> _oneDot() => [
      {
        'id': 'd1',
        'seq': 1,
        'over_number': 1,
        'ball_in_over': 1,
        'bowler_id': 'b1',
        'striker_id': 's1',
        'non_striker_id': 's2',
        'runs_off_bat': 0,
        'extra_wides': 0,
        'extra_no_ball_penalty': 0,
        'extra_byes': 0,
        'extra_leg_byes': 0,
        'extra_penalty': 0,
        'is_legal': true,
        'wicket_type': null,
        'dismissed_player_id': null,
        'incoming_batter_id': null,
        'fielder_id': null,
        'event_kind': null,
      },
    ];

Widget _screen(_SpyRepo spy) => ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(spy),
        matchProvider(_matchId)
            .overrideWith((ref) async => {'id': _matchId, 'balls_per_over': 6}),
        currentInningsProvider(_matchId).overrideWith((ref) async => {
              'id': _inningsId,
              'batting_team_id': 'ta',
              'bowling_team_id': 'tb',
            }),
        matchSquadProvider(_matchId).overrideWith((ref) async => [
              for (final m in const [
                ('s1', 'S1', 'ta'),
                ('s2', 'S2', 'ta'),
                ('b1', 'B1', 'tb'),
              ])
                {
                  'team_id': m.$3,
                  'team_member_id': m.$1,
                  'batting_order': 1,
                  'is_captain': false,
                  'is_wicket_keeper': false,
                  'team_members': {
                    'id': m.$1,
                    'guest_name': m.$2,
                    'profiles': null,
                  },
                },
            ]),
        inningsDeliveriesProvider(_inningsId)
            .overrideWith((ref) async => _oneDot()),
      ],
      child: const MaterialApp(home: BallLogScreen(matchId: _matchId)),
    );

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byType(ListTile).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit this ball'));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a dot re-marked as a wide reaches the RPC as a wide on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_screen(spy));
        await tester.pumpAndSettle();
        await _openEditor(tester);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Wide'));
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Save');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();

        expect(spy.editCalls, 1, reason: 'sanity: it saved once');
        expect(spy.sawWides, greaterThanOrEqualTo(1),
            reason: 'the umpire signalled a beat after the scorer tapped 0. '
                'Choosing Wide has to travel to the RPC - the chip existing on '
                'screen proves nothing, which is the same gap that let a '
                'dropped _crossed parameter pass every test earlier today');
        expect(spy.sawRuns, 0,
            reason: 'and nothing comes off the bat on a wide');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: leaving the delivery alone sends no wide on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_screen(spy));
        await tester.pumpAndSettle();
        await _openEditor(tester);

        final save = find.widgetWithText(FilledButton, 'Save');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();

        expect(spy.sawWides, 0,
            reason: 'a save that did not touch the delivery type must not '
                'invent an extra - otherwise every correction quietly adds a '
                'run to the total');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
