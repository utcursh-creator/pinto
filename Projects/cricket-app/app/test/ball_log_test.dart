import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/ball_log_screen.dart';

List<Map<String, dynamic>> _deliveries() => [
      {
        'id': 'd1', 'seq': 1, 'bowler_id': 'b1', 'striker_id': 's1',
        'non_striker_id': 's2', 'runs_off_bat': 4, 'extra_wides': 0,
        'extra_no_ball_penalty': 0, 'extra_byes': 0, 'extra_leg_byes': 0,
        'is_legal': true, 'wicket_type': null, 'dismissed_player_id': null,
        'incoming_batter_id': null, 'fielder_id': null,
      },
      {
        'id': 'd2', 'seq': 2, 'bowler_id': 'b1', 'striker_id': 's2',
        'non_striker_id': 's1', 'runs_off_bat': 0, 'extra_wides': 1,
        'extra_no_ball_penalty': 0, 'extra_byes': 0, 'extra_leg_byes': 0,
        'is_legal': false, 'wicket_type': null, 'dismissed_player_id': null,
        'incoming_batter_id': null, 'fielder_id': null,
      },
      {
        'id': 'd3', 'seq': 3, 'bowler_id': 'b1', 'striker_id': 's2',
        'non_striker_id': 's1', 'runs_off_bat': 0, 'extra_wides': 0,
        'extra_no_ball_penalty': 0, 'extra_byes': 0, 'extra_leg_byes': 0,
        'is_legal': true, 'wicket_type': 'bowled', 'dismissed_player_id': null,
        'incoming_batter_id': 's3', 'fielder_id': null,
      },
    ];

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchProvider.overrideWith((ref, id) async =>
            {'id': 'm1', 'balls_per_over': 6, 'team_a_id': 'A', 'team_b_id': 'B'}),
        currentInningsProvider.overrideWith((ref, id) async => {
              'id': 'in1', 'innings_number': 1,
              'batting_team_id': 'A', 'bowling_team_id': 'B',
              'status': 'live', 'target': null,
            }),
        matchSquadProvider.overrideWith((ref, id) async => [
              {'team_id': 'A', 'team_member_id': 's1', 'team_members': {'guest_name': 'Rohit', 'profiles': null}},
              {'team_id': 'A', 'team_member_id': 's2', 'team_members': {'guest_name': 'Gill', 'profiles': null}},
              {'team_id': 'A', 'team_member_id': 's3', 'team_members': {'guest_name': 'Kohli', 'profiles': null}},
              {'team_id': 'B', 'team_member_id': 'b1', 'team_members': {'guest_name': 'Bumrah', 'profiles': null}},
            ]),
        inningsDeliveriesProvider.overrideWith((ref, id) async => _deliveries()),
      ],
      child: const MaterialApp(home: BallLogScreen(matchId: 'm1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('ball log lists deliveries with outcomes on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('4'), findsOneWidget); // a boundary
        expect(find.text('Wd'), findsOneWidget); // a wide
        expect(find.textContaining('W bowled'), findsOneWidget); // a wicket
        expect(find.text('Bumrah  to  Rohit'), findsOneWidget); // bowler->striker
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('tapping a ball offers edit/insert/delete on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.text('4'));
        await tester.pumpAndSettle();
        expect(find.text('Edit this ball'), findsOneWidget);
        expect(find.text('Insert a ball after this'), findsOneWidget);
        expect(find.text('Delete this ball'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('edit opens a prefilled editor on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.text('4'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit this ball'));
        await tester.pumpAndSettle();
        expect(find.text('Edit ball'), findsOneWidget);
        // SCOR-18: the editor composes independent fields, not one "type"
        expect(find.text('Delivery'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Wide'), findsOneWidget);
        expect(find.text('Byes'), findsOneWidget);
        expect(find.text('Leg-byes'), findsOneWidget);
        expect(find.text('+5 penalty runs'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('insert requires a bowler on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.text('4'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Insert a ball after this'));
        await tester.pumpAndSettle();
        expect(find.text('Insert a ball'), findsOneWidget);
        // bowler picker is present for insert
        expect(find.byKey(const Key('editor_bowler')), findsOneWidget);
        // Insert button is disabled until a bowler is chosen
        final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Insert ball'),
        );
        expect(btn.onPressed, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('delete asks for confirmation on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester);
        await tester.tap(find.text('4'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete this ball'));
        await tester.pumpAndSettle();
        expect(find.text('Delete this ball?'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
