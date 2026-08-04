import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Whole-system review #2 (2026-07-28): deleting the last ball of an over from
/// the ball log leaves the console unable to name the bowler whose over it is.
///
/// Bowler X finishes an over, so `_afterBall` files X as `_lastOverBowlerId`
/// and clears `_bowlerId`. The scorer then opens the Ball log - a `push`, so the
/// console State stays alive underneath - and deletes that sixth delivery. The
/// ball log invalidates `inningsStateProvider`, the console rebuilds showing
/// 0.5 overs, and the over is open again. It is still X's over.
///
/// But `_bowlerId` is still null and `_lastOverBowlerId` is still X, so the pad
/// stays behind its AbsorbPointer and the picker renders X as "Bowled last
/// over", disabled. The only selectable bowlers are the WRONG ones, and picking
/// Y credits the rest of X's over to Y - permanently, through the career-stats
/// re-fold. The only escape is to leave and re-enter the console, which nothing
/// tells the scorer.
///
/// `_undo()` already reconciles exactly this. The recovery just lived inside
/// that one handler instead of reacting to the fold, so every OTHER route to
/// the same state - a ball-log delete, a ball-log insert, or another device
/// scoring over realtime - was left stranded.
class _LegalN extends Notifier<int> {
  @override
  int build() => 5;
  void set(int v) => state = v;
}

final _legalSrc = NotifierProvider<_LegalN, int>(_LegalN.new);

class _BumpRepo extends Fake implements MatchRepository {
  _BumpRepo(this.onBall, this.onUndo);
  final void Function() onBall;
  final void Function() onUndo;

  @override
  Future<void> undoLastBall(String inningsId) async => onUndo();

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
    onBall();
    return (deliveryId: 'd1', wagonApplicable: false);
  }
}

late ProviderContainer _c;

Future<void> _pump(WidgetTester tester) async {
  _c = ProviderContainer(overrides: [
    matchRepositoryProvider
        .overrideWithValue(_BumpRepo(
      () => _c.read(_legalSrc.notifier).set(6),
      () => _c.read(_legalSrc.notifier).set(5),
    )),
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
    bowlerOverCapProvider.overrideWith((ref, id) async => null),
    // the fold, driven by _legalSrc so a test can reopen an over the way a
    // ball-log delete does
    inningsStateProvider.overrideWith((ref, id) async {
      final legal = ref.watch(_legalSrc);
      return {
        'runs': 30,
        'wickets': 1,
        'wickets_remaining': 9,
        'legal_balls': legal,
        'over': '${legal ~/ 6}.${legal % 6}',
        'striker_id': 's1',
        'non_striker_id': 's2',
        'last_seq': legal,
      };
    }),
  ]);
  addTearDown(_c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: _c,
    child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
  ));
  await tester.pumpAndSettle();
}

/// 5 balls gone, Bumrah bowling; the 6th (a bye) completes his over.
Future<void> _completeBumrahsOver(WidgetTester tester) async {
  await tester.tap(find.text('Pick'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bumrah'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('B'));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('deleting an over\'s last ball resumes that bowler '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await _completeBumrahsOver(tester);
        expect(find.text('Select a bowler to start the over'), findsOneWidget,
            reason: 'sanity: the over ended, so a new bowler is needed');

        // the scorer opens the ball log and deletes that sixth delivery; the
        // fold drops back to 0.5 overs and the over is open again
        _c.read(_legalSrc.notifier).set(5);
        await tester.pumpAndSettle();

        expect(find.text('Bowling: Bumrah'), findsOneWidget,
            reason: 'the over is open again and it is still Bumrah\'s over - '
                'picking anyone else credits the rest of it to the wrong '
                'bowler, permanently, through the career-stats re-fold');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('and he is not branded "Bowled last over" on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await _completeBumrahsOver(tester);
        _c.read(_legalSrc.notifier).set(5);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        expect(find.text('Bowled last over'), findsNothing,
            reason: 'his over is the one in progress, so he must be the one '
                'the scorer CAN pick');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('REGRESSION GUARD: Undo still resumes the bowler too '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // This recovery used to live inside _undo(). Moving it onto the fold
        // must not cost undo the behaviour it already had - deleting working
        // code is only safe if something still pins what it did.
        await _pump(tester);
        await _completeBumrahsOver(tester);
        expect(find.text('Select a bowler to start the over'), findsOneWidget);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        expect(find.text('Bowling: Bumrah'), findsOneWidget,
            reason: 'undoing the ball that ended the over reopens it, and it '
                'is still his over');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: a completed over still demands a new bowler '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // Nothing is deleted here. If the fix resumed the last bowler whenever
        // _bowlerId was null it would silently re-select him at the start of
        // every new over - letting one man bowl consecutive overs, which the
        // Laws forbid and record_ball rejects.
        await _pump(tester);
        await _completeBumrahsOver(tester);
        await tester.pumpAndSettle();

        expect(find.text('Select a bowler to start the over'), findsOneWidget);
        expect(find.text('Bowling: Bumrah'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
