import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Regression locks for the HIGH frontend defects found by the 2026-07-07
/// penetration review.
///
/// REWRITTEN 2026-08-05. Whole-system review #2 findings 50, 69 and 32: all
/// three groups in this file passed without touching the app.
///
///   50 - the no-ball enum test defined its OWN copy of the mapping under a
///        comment saying it "mirrors _nbKindEnum", then asserted the copy was
///        right. Reverting the console to the shipped bug ('byes' instead of
///        'bye', which made every no-ball that went for byes a hard Postgres
///        400 that could not be scored at all) left this green. Its sibling
///        asserted only that the test's own const set lacked two strings, which
///        cannot fail for any state of the app.
///   69 - the whole body was `const sig = MatchRepository.new; expect(sig,
///        isNotNull);`. A constructor tearoff is never null, and it is the
///        CONSTRUCTOR, while penalty/isOverthrow/expectedLastSeq are named
///        parameters of recordBall. Deleting every one of them left it green.
///   32 - the credentials test computed `kDebugMode ? 'dev@pitch.local' : ''`
///        INSIDE the test and asserted on its own arithmetic. Removing the
///        kDebugMode gate from the real screen - the fix that stopped a live
///        hosted credential shipping inside the release binary - left it green.
///
/// Each now goes through the code it claims to cover.
class _SpyRepo extends Fake implements MatchRepository {
  String? sawKind;
  int? sawPenalty;
  bool? sawOverthrow;
  int? sawExpectedLastSeq;
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
    sawKind = noballSecondaryKind;
    sawPenalty = penalty;
    sawOverthrow = isOverthrow;
    sawExpectedLastSeq = expectedLastSeq;
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
        bowlerOverCapProvider.overrideWith((ref, id) async => null),
        inningsStateProvider.overrideWith((ref, id) async => {
              'runs': 10,
              'wickets': 0,
              'wickets_remaining': 10,
              'legal_balls': 8,
              'over': '1.2',
              'striker_id': 's1',
              'non_striker_id': 's2',
              'last_seq': 33,
            }),
      ],
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );

Future<void> _pickBowlerAndOpenExtras(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pick'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bumrah'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Extras'));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('50: a no-ball that went for byes sends the SINGULAR enum '
        'on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_console(spy));
        await _pickBowlerAndOpenExtras(tester);

        await tester.tap(find.widgetWithText(ChoiceChip, 'No-ball'));
        await tester.pumpAndSettle();
        // "Byes" appears twice once No-ball is chosen: the delivery type, and
        // "The runs came from". The second group renders after the first.
        await tester.tap(find.widgetWithText(ChoiceChip, 'Byes').last);
        await tester.pumpAndSettle();
        // the secondary kind is only sent when runs were actually run
        await tester.tap(find.byIcon(Icons.add_circle_outline).first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Record'));
        await tester.pumpAndSettle();

        expect(spy.calls, 1, reason: 'the ball was recorded');
        expect(spy.sawKind, 'bye',
            reason: 'public.noball_secondary_kind is SINGULAR. The console once '
                'sent the plural pad key, which made every no-ball that went '
                'for byes a hard Postgres 400 - the delivery could not be '
                'scored at all. This now goes through the real _nbKindEnum '
                'instead of a copy of it kept in the test.');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('69: the pad actually passes penalty, overthrow and the '
        'stale-write fence on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final spy = _SpyRepo();
        await tester.pumpWidget(_console(spy));
        await _pickBowlerAndOpenExtras(tester);

        await tester
            .tap(find.widgetWithText(SwitchListTile, 'Includes overthrows'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('+5 penalty runs'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Record'));
        await tester.pumpAndSettle();

        expect(spy.calls, 1);
        expect(spy.sawPenalty, 5,
            reason: 'SCOR-7: the penalty switch has to reach the RPC');
        expect(spy.sawOverthrow, isTrue,
            reason: 'SCOR-7: so does the overthrow flag');
        expect(spy.sawExpectedLastSeq, 33,
            reason: 'SCOR-24: the stale-write fence carries the version this '
                'tap was decided against. The old test asserted a constructor '
                'tearoff was non-null, and would have passed with all three of '
                'these parameters deleted from the repository.');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('32: the dev credential prefill is gated on kDebugMode in the SCREEN',
      () {
    // The old test computed the prefill itself and asserted on its own
    // arithmetic, so deleting the gate from the screen left it green - and that
    // gate is what stopped a live hosted credential shipping inside the release
    // binary, where anyone with the APK could sign in as that identity.
    final src = File('lib/src/features/auth/presentation/sign_in_screen.dart')
        .readAsStringSync();
    for (final secret in ['dev@pitch.local', 'password123']) {
      final at = src.indexOf(secret);
      expect(at, isNot(-1),
          reason: 'anchor lost - this guard is checking nothing');
      final declStart = src.lastIndexOf('TextEditingController', at);
      expect(declStart, isNot(-1),
          reason: 'the literal is no longer in a controller initialiser; '
              're-anchor this guard rather than deleting it');
      expect(src.substring(declStart, at), contains('kDebugMode'),
          reason: '"$secret" is a REAL account on the hosted project, so '
              'without the kDebugMode gate it is prefilled inside the release '
              'binary');
    }
  });
}
