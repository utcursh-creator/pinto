import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Whole-system review #2 (2026-07-28), finding 79: the "+5 penalty runs" switch
/// always credits the BATTING side, including for the case its own subtitle
/// named.
///
/// The subtitle read "Ball hit a helmet, deliberate short run, etc." A
/// deliberate short run is a penalty awarded to the FIELDING side. A scorer
/// following that instruction handed the batting side the 5 runs it had just
/// been penalised - a 10-run swing, which in a chase also moves the required
/// rate and can hand the batting side a win it did not earn.
///
/// deliveries.extra_penalty only ever accrues to the innings being folded, so
/// penalties AGAINST the batting side are not modelled at all. Inventing a
/// schema for them is a feature, not a bug fix, and is deliberately NOT done
/// here - so the control says exactly what it does and names only cases that
/// go that way. Recording a deliberate short run correctly remains unsupported,
/// which is a smaller problem than recording it backwards.
class _NoopRepo extends Fake implements MatchRepository {}

Widget _console() => ProviderScope(
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
            ]),
        bowlerOverCapProvider.overrideWith((ref, id) async => null),
        inningsStateProvider.overrideWith((ref, id) async => {
              'runs': 40,
              'wickets': 1,
              'wickets_remaining': 9,
              'legal_balls': 30,
              'over': '5.0',
              'striker_id': 's1',
              'non_striker_id': 's2',
              'last_seq': 30,
            }),
      ],
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the penalty switch does not tell the scorer to use it for a '
        'deliberate short run on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_console());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bumrah'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Extras'));
        await tester.pumpAndSettle();

        // the switch exists and states its direction
        expect(find.textContaining('penalty runs to the batting side'),
            findsOneWidget,
            reason: 'the control credits the batting side and only the batting '
                'side, so it should say so');

        final subtitle = find.textContaining('deliberate short run');
        expect(subtitle, findsOneWidget,
            reason: 'the case is worth naming - it is the trap');
        final text = tester.widget<Text>(subtitle).data!;
        expect(text.toUpperCase(), contains('NOT'),
            reason: 'the old copy INSTRUCTED the scorer to use this for a '
                'deliberate short run, which penalises the batting side - '
                'following it handed them the 5 runs they had just lost, a '
                '10-run swing that can decide a chase');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
