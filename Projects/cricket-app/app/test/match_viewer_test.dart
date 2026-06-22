import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_viewer_screen.dart';

/// A realistic single-innings fold (mid-innings, chasing nothing yet).
Map<String, dynamic> _fold() => {
      'runs': 45,
      'wickets': 2,
      'legal_balls': 38,
      'over': '6.2',
      'extras': {'wides': 2, 'no_balls': 1, 'byes': 0, 'leg_byes': 1, 'penalty': 0},
      'striker_id': 's1',
      // s4 is at the crease but has not faced a ball yet: it must render as a
      // "0*" batting row and be excluded from "Did not bat".
      'non_striker_id': 's4',
      'free_hit_active': false,
      'batting': [
        {'batter_id': 's1', 'runs': 28, 'balls': 20, 'fours': 3, 'sixes': 1},
        {'batter_id': 's2', 'runs': 12, 'balls': 15, 'fours': 1, 'sixes': 0},
      ],
      'bowling': [
        {
          'bowler_id': 'b1',
          'legal_balls': 18,
          'runs_conceded': 26,
          'maidens': 0,
          'dots': 6,
          'wides_bowled': 2,
          'no_balls_bowled': 1,
          'wickets': 1,
          'overs': '3.0',
          'economy': 8.67,
        },
      ],
      'fall_of_wickets': [
        {'wicket_number': 1, 'score_at_fall': 15, 'over': '2.3', 'dismissed_player_id': 's3'},
      ],
      'partnerships': [],
      'current_partnership': {
        'batter_a': 's1',
        'batter_b': 's2',
        'runs': 30,
        'balls': 25,
        'a_runs': 28,
        'b_runs': 12,
      },
      'per_over': [
        {'over_number': 1, 'runs_in_over': 6, 'wickets_in_over': 0},
        {'over_number': 2, 'runs_in_over': 9, 'wickets_in_over': 1},
        {'over_number': 3, 'runs_in_over': 12, 'wickets_in_over': 0},
      ],
      'worm': [
        {'over': 1, 'cumulative_runs': 6, 'cumulative_wickets': 0},
        {'over': 2, 'cumulative_runs': 15, 'cumulative_wickets': 1},
        {'over': 3, 'cumulative_runs': 27, 'cumulative_wickets': 1},
      ],
      'did_not_bat': ['s4', 's7'],
      'crr': 7.1,
      'rrr': null,
      'runs_required': null,
      'balls_remaining': 82,
      'wickets_remaining': 8,
      'innings_status': 'in_progress',
      'result': null,
      'orphaned_deliveries': [],
    };

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchProvider.overrideWith(
          (ref, id) async => {
            'id': 'm1',
            'team_a_id': 'A',
            'team_b_id': 'B',
            'venue': 'Shivaji Park',
            'overs_limit': 20,
            'balls_per_over': 6,
            'status': 'live',
            'toss_winner_id': 'A',
            'toss_decision': 'bat',
          },
        ),
        matchTeamNamesProvider.overrideWith(
          (ref, id) async => {'A': 'Mumbai United', 'B': 'Dadar CC'},
        ),
        matchInningsListProvider.overrideWith(
          (ref, id) async => [
            {
              'id': 'in1',
              'innings_number': 1,
              'batting_team_id': 'A',
              'bowling_team_id': 'B',
              'status': 'in_progress',
              'target': null,
            },
          ],
        ),
        matchSquadProvider.overrideWith(
          (ref, id) async => [
            {'team_id': 'A', 'team_member_id': 's1', 'team_members': {'guest_name': 'Rahul', 'profiles': null}},
            {'team_id': 'A', 'team_member_id': 's2', 'team_members': {'guest_name': 'Arjun', 'profiles': null}},
            {'team_id': 'A', 'team_member_id': 's3', 'team_members': {'guest_name': 'Sachin', 'profiles': null}},
            {'team_id': 'A', 'team_member_id': 's4', 'team_members': {'guest_name': 'Vinod', 'profiles': null}},
            {'team_id': 'A', 'team_member_id': 's7', 'team_members': {'guest_name': 'Pavan', 'profiles': null}},
            {'team_id': 'B', 'team_member_id': 'b1', 'team_members': {'guest_name': 'Imran', 'profiles': null}},
          ],
        ),
        inningsStateProvider.overrideWith((ref, id) async => _fold()),
        inningsWagonProvider.overrideWith(
          (ref, id) async => [
            {'wagon_x': 0.7, 'wagon_y': 0.4, 'runs_off_bat': 4},
          ],
        ),
      ],
      child: const MaterialApp(
        home: MatchViewerScreen(matchId: 'm1', enableRealtime: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Live tab shows score + teams + striker on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('45/2'), findsOneWidget);
        expect(find.textContaining('6.2'), findsWidgets);
        expect(find.text('Mumbai United'), findsWidgets);
        // current striker is marked
        expect(find.textContaining('Rahul'), findsWidgets);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Scorecard tab shows batting + bowling cards on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.text('Scorecard'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // batter row: name (striker carries a not-out '*') + score
        expect(find.textContaining('Rahul'), findsWidgets);
        expect(find.text('28'), findsWidgets);
        // bowling section present
        expect(find.text('Bowling'), findsWidgets);
        expect(find.text('Imran'), findsWidgets);
        // extras line
        expect(find.textContaining('Extras'), findsWidgets);
        // a not-yet-faced batter at the crease (Vinod) shows as a batting row,
        // and "Did not bat" lists only the genuinely-not-out player (Pavan).
        expect(find.textContaining('Vinod'), findsWidgets);
        final dnb = tester.widget<Text>(find.textContaining('Did not bat'));
        expect(dnb.data, contains('Pavan'));
        expect(dnb.data, isNot(contains('Vinod')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Charts tab renders Manhattan + worm on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.text('Charts'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('manhattan_chart')), findsOneWidget);
        expect(find.byKey(const Key('worm_chart')), findsOneWidget);
        // wagon wheel is below the fold in the charts list
        await tester.scrollUntilVisible(
          find.byKey(const Key('wagon_chart')),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.byKey(const Key('wagon_chart')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Share action opens a branded card on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.byIcon(Icons.ios_share));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Pitch'), findsOneWidget);
        expect(find.text('45/2'), findsWidgets);
        expect(find.widgetWithText(FilledButton, 'Share image'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Info tab shows venue + toss + format on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.text('Info'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Shivaji Park'), findsWidgets);
        expect(find.textContaining('20'), findsWidgets);
        expect(find.textContaining('Toss'), findsWidgets);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
