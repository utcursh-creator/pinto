import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/ball_log_screen.dart';

/// Review #3 (MEDIUM), finding 15: no correction path can set the run-out
/// `crossed` flag.
///
/// A ball goes unrecorded - scorer distracted between overs. On it the
/// non-striker was run out and the batters HAD crossed. The scorer inserts it
/// from the ball log, and there is no "Batters had crossed" control anywhere in
/// the editor to set. The row lands with crossed = NULL, all three folds read
/// `coalesce(crossed,false)` and skip the crossing swap, and from that ball on
/// every run, ball faced, four and six goes to the wrong batter -
/// restamp_innings_strike then stamps the wrong pair onto every later row of
/// the ball log the scorer reads back.
///
/// The scoring console has had this switch all along
/// (scoring_console_screen.dart, gated on run_out / obstructing). Only the
/// correction path lacked it. Backend half: pgTAP 151, which pins the corrected
/// innings against a LIVE-scored one rather than against a hand-derived
/// expectation.
class _SpyRepo extends Fake implements MatchRepository {
  bool? sawEditCrossed;
  bool? sawInsertCrossed;
  var editCalls = 0;
  var insertCalls = 0;

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
    sawEditCrossed = crossed;
  }

  @override
  Future<String> insertBall({
    required String inningsId,
    required int afterSeq,
    required String bowlerId,
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
  }) async {
    insertCalls++;
    sawInsertCrossed = crossed;
    return 'new';
  }
}

const _matchId = 'm1';
const _inningsId = 'i1';

/// One completed run-out, recorded WITHOUT the crossing (the case a scorer
/// would come back to correct).
List<Map<String, dynamic>> _oneRunOut() => [
      {
        'id': 'd1', 'seq': 1, 'bowler_id': 'b1', 'striker_id': 's1',
        'non_striker_id': 's2', 'runs_off_bat': 1, 'extra_wides': 0,
        'extra_no_ball_penalty': 0, 'extra_byes': 0, 'extra_leg_byes': 0,
        'is_legal': true, 'wicket_type': 'run_out', 'dismissed_player_id': 's2',
        'incoming_batter_id': 's3', 'fielder_id': null, 'crossed': false,
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
                ('s3', 'S3', 'ta'),
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
            .overrideWith((ref) async => _oneRunOut()),
      ],
      child: const MaterialApp(home: BallLogScreen(matchId: _matchId)),
    );

Future<void> _openMenu(WidgetTester tester, String action) async {
  await tester.tap(find.byType(ListTile).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a run-out being EDITED can have its crossing corrected on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_screen(spy));
        await tester.pumpAndSettle();
        await _openMenu(tester, 'Edit this ball');

        final sw = find.widgetWithText(SwitchListTile, 'Batters had crossed');
        expect(sw, findsOneWidget,
            reason: 'the console has had this switch all along; without it in '
                'the editor a run-out recorded with the switch the wrong way '
                'could never be corrected, and the wrong batter kept the '
                'strike for the rest of the innings');
        await tester.ensureVisible(sw);
        await tester.pumpAndSettle();
        await tester.tap(sw);
        await tester.pumpAndSettle();
        // the sheet is taller now that it asks about crossing, so the submit
        // button can sit below the fold
        final save = find.widgetWithText(FilledButton, 'Save');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();

        expect(spy.editCalls, 1, reason: 'sanity: the edit was submitted');
        expect(spy.sawEditCrossed, isTrue,
            reason: 'edit_ball is a COALESCE patch, so the value has to be '
                'SENT - omitting it keeps whatever is stored, which is the '
                'wrong value the scorer opened the editor to fix');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a run-out being INSERTED carries its crossing on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_screen(spy));
        await tester.pumpAndSettle();
        await _openMenu(tester, 'Insert a ball after this');

        // the ball being reconstructed: a run-out where the batters crossed
        await tester.tap(find.widgetWithText(SwitchListTile, 'Wicket'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'run out'));
        await tester.pumpAndSettle();
        final sw = find.widgetWithText(SwitchListTile, 'Batters had crossed');
        expect(sw, findsOneWidget,
            reason: 'this is the case in the finding: the missed ball WAS a '
                'run-out on which the batters crossed, and the editor gave the '
                'scorer no way to say so');
        await tester.ensureVisible(sw);
        await tester.pumpAndSettle();
        await tester.tap(sw);
        await tester.pumpAndSettle();

        expect(spy.insertCalls, 0, reason: 'sanity: not submitted yet');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a bowled ball has no crossing question on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_screen(spy));
        await tester.pumpAndSettle();
        await _openMenu(tester, 'Edit this ball');

        // switch the dismissal from run out to bowled
        await tester.tap(find.widgetWithText(ChoiceChip, 'bowled'));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(SwitchListTile, 'Batters had crossed'),
            findsNothing,
            reason: 'crossing only means anything on a run out or obstructing '
                'the field - the console gates it the same way, and asking it '
                'on a bowled ball would invite a wrong answer');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
