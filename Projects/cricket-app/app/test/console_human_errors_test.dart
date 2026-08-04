import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Whole-system review #2 (2026-07-28): the scoring console dumps raw exception
/// text at the user.
///
/// `humanError()` exists and is used in 78 places, but the console - the one
/// screen somebody operates under time pressure, standing at a boundary rope
/// with a match going on - still had four `_toast('$e')` sites. A failed ball
/// showed
///
///   PostgrestException(message: new row violates row-level security policy
///   for table "deliveries", code: 42501, details: null, hint: null)
///
/// which reads as a crash, and is the ONLY feedback the scorer gets. They
/// cannot tell whether the ball was recorded.
///
/// The fix must NOT flatten everything to "Something went wrong": our RPCs
/// raise P0001 with copy written deliberately for this user ("bowler cannot
/// bowl consecutive overs"), and that copy is the whole point. humanError()
/// keeps human-written messages and scrubs machine noise - the second test
/// pins that, so the fix cannot be a blanket catch-all.
class _ThrowingRepo extends Fake implements MatchRepository {
  _ThrowingRepo(this.error);
  final Object error;

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
  }) async => throw error;
}

Widget _console(Object error) => ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(_ThrowingRepo(error)),
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
              'wickets': 1,
              'wickets_remaining': 9,
              'legal_balls': 8,
              'over': '1.2',
              'striker_id': 's1',
              'non_striker_id': 's2',
              'last_seq': 33,
            }),
      ],
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );

Future<void> _recordAWide(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pick'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bumrah'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Wd'));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a failed ball does not show Postgres internals on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_console(PostgrestException(
          message: 'new row violates row-level security policy for table '
              '"deliveries"',
          code: '42501',
        )));
        await _recordAWide(tester);

        expect(find.textContaining('PostgrestException'), findsNothing,
            reason: 'the scorer is mid-match - a raw exception reads as a '
                'crash and tells them nothing about whether the ball landed');
        expect(find.textContaining('row-level security'), findsNothing);
        expect(find.text('You do not have permission to do that.'),
            findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('but a message we wrote for the scorer survives on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // CONTROL: our own RAISE. Replacing this with a generic apology would
        // be a REGRESSION - it is the only thing that tells the scorer why the
        // ball was refused and what to do instead.
        await tester.pumpWidget(_console(PostgrestException(
          message: 'bowler cannot bowl consecutive overs',
          code: 'P0001',
        )));
        await _recordAWide(tester);

        expect(find.text('Bowler cannot bowl consecutive overs.'),
            findsOneWidget,
            reason: 'humanError keeps copy we wrote on purpose - the fix must '
                'not flatten every failure into "Something went wrong"');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  // The behavioural tests above can only reach the record path. The console has
  // three more raw sites (innings close, next innings, retire) that no mocked
  // test drives, and they fail exactly when a real match is going wrong. Guard
  // them at the source instead of pretending they are covered.
  test('no raw exception is interpolated into a console toast', () {
    final src = File('lib/src/features/scoring/presentation/'
            'scoring_console_screen.dart')
        .readAsStringSync();
    final offenders = RegExp(r"_toast\(\s*(raw|'\$e')\s*\)").allMatches(src);
    expect(offenders, isEmpty,
        reason: 'found ${offenders.length} site(s) still dumping a raw '
            'exception at the scorer; wrap them in humanError(e, fallback: ...)');
  });
}
