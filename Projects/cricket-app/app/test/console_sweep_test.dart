import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_squads_screen.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

/// Sweep Unit B: the console UX roots - CRR (SCOR-21), swap/retire (SCOR-16),
/// orphan warning (SCOR-9), no-bowler feedback (SCOR-19), bowler figures +
/// over cap (SCOR-15), full extras composer (SCOR-7), and the squads screen's
/// batting order + captain/keeper capture (SCOR-13).
void main() {
  Widget console({
    Map<String, dynamic> state = const {},
    Map<String, dynamic> match = const {'balls_per_over': 6, 'status': 'live'},
  }) {
    return ProviderScope(
      overrides: [
        matchProvider.overrideWith((ref, id) async => match),
        currentInningsProvider.overrideWith(
          (ref, id) async => {
            'id': 'in1',
            'batting_team_id': 'A',
            'bowling_team_id': 'B',
            'target': null,
          },
        ),
        matchSquadProvider.overrideWith(
          (ref, id) async => [
            {
              'team_id': 'A',
              'team_member_id': 's1',
              'team_members': {'guest_name': 'Rahul', 'profiles': null},
            },
            {
              'team_id': 'A',
              'team_member_id': 's2',
              'team_members': {'guest_name': 'Arjun', 'profiles': null},
            },
            {
              'team_id': 'B',
              'team_member_id': 'b1',
              'team_members': {'guest_name': 'Bumrah', 'profiles': null},
            },
            {
              'team_id': 'B',
              'team_member_id': 'b2',
              'team_members': {'guest_name': 'Shami', 'profiles': null},
            },
          ],
        ),
        inningsStateProvider.overrideWith(
          (ref, id) async => {
            'runs': 42,
            'wickets': 1,
            'over': '5.2',
            'striker_id': 's1',
            'non_striker_id': 's2',
            'crr': 7.88,
            'last_seq': 33,
            ...state,
          },
        ),
      ],
      child: const MaterialApp(home: ScoringConsoleScreen(matchId: 'm1')),
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('console header shows CRR on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(console());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('CRR 7.88'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('console offers swap strike + retire on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(console());
        await tester.pumpAndSettle();
        expect(find.text('Swap strike'), findsOneWidget);
        expect(find.text('Retire'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('orphaned deliveries surface a warning on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(console(state: {
          'orphaned_deliveries': ['x', 'y'],
        }));
        await tester.pumpAndSettle();
        expect(
            find.textContaining('2 balls recorded after the innings ended'),
            findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('tapping the dead pad explains + opens the bowler picker on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(console());
        await tester.pumpAndSettle();
        // no bowler picked yet - the pad is absorbed; tap where "0" sits
        await tester.tap(find.text('0'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('Pick a bowler to start the over'), findsWidgets);
        expect(find.text('Select bowler'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('bowler picker shows figures and blocks the capped bowler on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(console(
          match: {
            'balls_per_over': 6,
            'status': 'live',
            'rules': {'max_overs_per_bowler': 1},
          },
          state: {
            'bowling': [
              {
                'bowler_id': 'b1',
                'legal_balls': 6,
                'overs': '1.0',
                'runs_conceded': 9,
                'wickets': 1,
              },
            ],
          },
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();
        expect(find.text('Max 1 overs each'), findsOneWidget);
        expect(find.text('1.0 ov - 9 runs - 1 wkt'), findsOneWidget);
        expect(find.text('At over limit'), findsOneWidget);
        expect(find.text('Yet to bowl'), findsOneWidget);
        // the capped bowler's tile is disabled
        final capped = tester.widget<ListTile>(find.ancestor(
            of: find.text('Bumrah'), matching: find.byType(ListTile)));
        expect(capped.enabled, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('extras sheet composes runs/penalty/overthrow on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(console());
        await tester.pumpAndSettle();
        // pick a bowler so the pad is live
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shami').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Extras'));
        await tester.pumpAndSettle();
        expect(find.text('This ball was'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Runs'), findsOneWidget);
        expect(find.text('Includes overthrows'), findsOneWidget);
        expect(find.text('+5 penalty runs on this ball'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('squads screen captures order + captain/keeper on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchProvider.overrideWith(
                (ref, id) async =>
                    {'id': 'm1', 'team_a_id': 'A', 'team_b_id': 'B'},
              ),
              matchTeamNamesProvider.overrideWith(
                (ref, id) async => {'A': 'Mumbai', 'B': 'Chennai'},
              ),
              teamMembersProvider.overrideWith(
                (ref, teamId) async => teamId == 'A'
                    ? [
                        {'id': 'a1', 'guest_name': 'Rohit', 'profiles': null},
                        {'id': 'a2', 'guest_name': 'Gill', 'profiles': null},
                      ]
                    : [
                        {'id': 'x1', 'guest_name': 'Dhoni', 'profiles': null},
                      ],
              ),
            ],
            child: const MaterialApp(home: MatchSquadsScreen(matchId: 'm1')),
          ),
        );
        await tester.pumpAndSettle();
        // pick both Mumbai players - order numbers appear
        await tester.tap(find.text('Rohit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gill'));
        await tester.pumpAndSettle();
        expect(find.text('1.  Rohit'), findsOneWidget);
        expect(find.text('2.  Gill'), findsOneWidget);
        // SCOR-13: with 2+ picked the captain/keeper selectors appear
        expect(find.text('Captain'), findsOneWidget);
        expect(find.text('Wicket-keeper'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
