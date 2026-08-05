import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/ball_log_screen.dart';

/// HIGH (whole-system review #2): a mis-tapped wicket could never be taken back.
///
/// edit_ball is COALESCE-patch shaped - omitting a field KEEPS it - so passing
/// `wicketType: null` did NOT remove the dismissal. The RPC has an explicit
/// `_clear_wicket` flag (pinned server-side by pgTAP 123) and the client never
/// sent it, so switching "Wicket" off in the ball-log editor was a silent no-op
/// and the batter stayed out on the scorecard forever.
class _SpyRepo extends Fake implements MatchRepository {
  bool? sawClearWicket;
  String? sawWicketType;

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
    sawClearWicket = clearWicket;
    sawWicketType = wicketType;
  }
}

const _matchId = 'm1';
const _inningsId = 'i1';

List<Map<String, dynamic>> _oneWicketBall() => [
      {
        'id': 'd1', 'seq': 1, 'bowler_id': 'b1', 'striker_id': 's1',
        'non_striker_id': 's2', 'runs_off_bat': 0, 'extra_wides': 0,
        'extra_no_ball_penalty': 0, 'extra_byes': 0, 'extra_leg_byes': 0,
        'is_legal': true, 'wicket_type': 'bowled', 'dismissed_player_id': 's1',
        'incoming_batter_id': 's3', 'fielder_id': null,
      },
    ];

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('turning Wicket off sends clearWicket on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            matchRepositoryProvider.overrideWithValue(spy),
            matchProvider(_matchId).overrideWith(
                (ref) async => {'id': _matchId, 'balls_per_over': 6}),
            currentInningsProvider(_matchId).overrideWith((ref) async => {
                  'id': _inningsId,
                  'batting_team_id': 'ta',
                  'bowling_team_id': 'tb',
                }),
            matchSquadProvider(_matchId).overrideWith((ref) async => [
                  {
                    'team_id': 'ta', 'team_member_id': 's1', 'batting_order': 1,
                    'is_captain': false, 'is_wicket_keeper': false,
                    'team_members': {'id': 's1', 'guest_name': 'S1', 'profiles': null},
                  },
                ]),
            inningsDeliveriesProvider(_inningsId)
                .overrideWith((ref) async => _oneWicketBall()),
          ],
          child: const MaterialApp(home: BallLogScreen(matchId: _matchId)),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit this ball'));
        await tester.pumpAndSettle();

        // switch the wicket OFF and save
        await tester.tap(find.widgetWithText(SwitchListTile, 'Wicket'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(spy.sawWicketType, isNull,
            reason: 'the editor reports no wicket');
        expect(spy.sawClearWicket, isTrue,
            reason: 'a null wicketType alone is NOT enough - edit_ball keeps '
                'what you omit, so the explicit clear flag must be sent or the '
                'batter stays out forever');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
