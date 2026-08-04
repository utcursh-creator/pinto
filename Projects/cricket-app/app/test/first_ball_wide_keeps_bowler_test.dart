import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Whole-system review #2 (2026-07-28): a wide on the first ball of an over
/// locked the bowler out of their own over.
///
/// `_afterBall` decides the over is finished with `legal % bpo == 0`. A wide
/// adds no legal ball, so immediately after an over ends (legal == 6) the very
/// next delivery being a wide leaves legal at 6 - still a multiple - and the
/// console concludes the over ended AGAIN. It clears `_bowlerId` and, worse,
/// files the bowler who has just started as `_lastOverBowlerId`, which the
/// picker renders as "Bowled last over" and refuses to select.
///
/// So the scorer sends down a first-ball wide and the man actually bowling is
/// the one person they are not allowed to pick. The only way out is to nominate
/// someone else - which is not cricket, and which record_ball would reject.
class _NoopRepo extends Fake implements MatchRepository {
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
  }) async => (deliveryId: 'd1', wagonApplicable: false);
}

/// [legalSeq] is what the fold reports on each successive read, so a test can
/// say "6 before the ball and 6 after" (a wide) or "5 before and 6 after" (the
/// legal ball that actually ends the over). The last value repeats.
Widget _console({required List<int> legalSeq}) {
  var i = 0;
  int nextLegal() {
    final v = legalSeq[i < legalSeq.length ? i : legalSeq.length - 1];
    i++;
    return v;
  }

  return ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(_NoopRepo()),
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
              {
                'team_id': 'B', 'team_member_id': 'b2',
                'team_members': {'guest_name': 'Shami', 'profiles': null},
              },
            ]),
        inningsStateProvider.overrideWith((ref, id) async {
          final legal = nextLegal();
          return {
            'runs': 42,
            'wickets': 1,
            'wickets_remaining': 9,
            'legal_balls': legal,
            'over': '${legal ~/ 6}.${legal % 6}',
            'striker_id': 's1',
            'non_striker_id': 's2',
            'last_seq': 33,
          };
        }),
      ],
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a wide on the first ball of an over keeps the bowler '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // an over has just ended: 6 legal balls, no bowler chosen yet
        await tester.pumpWidget(_console(legalSeq: const [6]));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bumrah'));
        await tester.pumpAndSettle();
        expect(find.text('Bowling: Bumrah'), findsOneWidget,
            reason: 'sanity: the new over has a bowler');

        // first ball of the new over is a wide - legal_balls does not move
        await tester.tap(find.text('Wd'));
        await tester.pumpAndSettle();

        expect(find.text('Bowling: Bumrah'), findsOneWidget,
            reason: 'a wide does not end an over - the bowler is mid-over and '
                'must stay selected');
        expect(find.text('Select a bowler to start the over'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('and the mid-over bowler is not branded "Bowled last over" '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_console(legalSeq: const [6]));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bumrah'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Wd'));
        await tester.pumpAndSettle();

        // open the picker and look at Bumrah's row
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        expect(find.text('Bowled last over'), findsNothing,
            reason: 'the bowler who is HALFWAY THROUGH this over must not be '
                'the one man the scorer cannot select');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a genuine sixth legal ball still ends the over on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // CONTROL: 5 legal balls bowled, the 6th completes the over. The fold
        // reports 6 afterwards, so the console must clear the bowler. Without
        // this the fix could simply be "never clear", which breaks cricket.
        await tester.pumpWidget(_console(legalSeq: const [5, 6]));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bumrah'));
        await tester.pumpAndSettle();
        expect(find.text('Bowling: Bumrah'), findsOneWidget);

        // a bye is a LEGAL delivery - this is the ball that ends the over
        await tester.tap(find.text('B'));
        await tester.pumpAndSettle();

        expect(find.text('Select a bowler to start the over'), findsOneWidget,
            reason: 'the over really did end - the console must ask for the '
                'next bowler, or the fix would just be "never clear"');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
