import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/stats/data/stats_models.dart';
import 'package:pitch_app/src/features/stats/data/stats_providers.dart';
import 'package:pitch_app/src/features/stats/presentation/player_stats_screen.dart';

Map<String, dynamic> _rich() => {
      'profile': {'display_name': 'Rahul', 'batting_style': 'right'},
      'career': {
        'player_key': 'p1',
        'matches': 5,
        'batting': {
          'innings': 4, 'not_outs': 1, 'runs': 80, 'balls': 60,
          'highest': 50, 'highest_not_out': true,
          'average': 80.0, 'strike_rate': 133.33,
          'fours': 6, 'sixes': 4, 'fifties': 1, 'hundreds': 0, 'ducks': 0,
        },
        'bowling': {
          'innings': 3, 'balls': 24, 'runs': 30, 'wickets': 6, 'maidens': 1,
          'overs': '4.0', 'best_wickets': 4, 'best_runs': 2,
          'average': 5.0, 'economy': 7.5, 'strike_rate': 4.0,
          'four_wickets': 1, 'five_wickets': 0,
        },
        'fielding': {'catches': 2, 'run_outs': 1, 'stumpings': 0},
      },
      'recent_form': [
        {'match_id': 'm1', 'bat': {'runs': 30, 'balls': 18, 'out': true, 'how_out': 'caught'},
          'bowl': {'wickets': 2, 'runs_conceded': 20, 'balls': 12}},
        {'match_id': 'm2', 'bat': {'runs': 12, 'balls': 10, 'out': false, 'how_out': null},
          'bowl': {'wickets': 0, 'runs_conceded': 0, 'balls': 0}},
      ],
    };

// A batter who has never been dismissed (average/SR-undefined paths) and never
// bowled wickets - the ratios must render as '-'.
Map<String, dynamic> _undefinedRatios() => {
      'profile': {'display_name': 'Sky', 'batting_style': 'right'},
      'career': {
        'player_key': 'p2', 'matches': 2,
        'batting': {
          'innings': 2, 'not_outs': 2, 'runs': 40, 'balls': 25,
          'highest': 22, 'highest_not_out': true,
          'average': null, 'strike_rate': 160.0,
          'fours': 4, 'sixes': 1, 'fifties': 0, 'hundreds': 0, 'ducks': 0,
        },
        'bowling': {
          'innings': 1, 'balls': 12, 'runs': 14, 'wickets': 0, 'maidens': 0,
          'overs': '2.0', 'best_wickets': 0, 'best_runs': 14,
          'average': null, 'economy': 7.0, 'strike_rate': null,
          'four_wickets': 0, 'five_wickets': 0,
        },
        'fielding': {'catches': 0, 'run_outs': 0, 'stumpings': 0},
      },
      'recent_form': const [],
    };

Map<String, dynamic> _empty() => {
      'profile': {'display_name': 'Newbie', 'batting_style': null},
      'career': {
        'player_key': 'p3', 'matches': 0,
        'batting': {
          'innings': 0, 'not_outs': 0, 'runs': 0, 'balls': 0,
          'highest': null, 'highest_not_out': false,
          'average': null, 'strike_rate': null,
          'fours': 0, 'sixes': 0, 'fifties': 0, 'hundreds': 0, 'ducks': 0,
        },
        'bowling': {
          'innings': 0, 'balls': 0, 'runs': 0, 'wickets': 0, 'maidens': 0,
          'overs': '0.0', 'best_wickets': null, 'best_runs': null,
          'average': null, 'economy': null, 'strike_rate': null,
          'four_wickets': 0, 'five_wickets': 0,
        },
        'fielding': {'catches': 0, 'run_outs': 0, 'stumpings': 0},
      },
      'recent_form': const [],
    };

Future<void> _pump(WidgetTester tester, Map<String, dynamic> json) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerStatsProvider
            .overrideWith((ref, id) async => PlayerStats.fromJson(json)),
      ],
      child: const MaterialApp(home: PlayerStatsScreen(profileId: 'p1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('model formatting', () {
    test('undefined ratios render as -', () {
      expect(fmtRatio(null), '-');
      expect(fmtRatio(80.0), '80.00');
      expect(fmtRatio(7.5), '7.50');
    });
    test('highest score is not-out aware', () {
      final s = PlayerStats.fromJson(_rich());
      expect(s.batting.highestLabel, '50*');
      expect(s.bowling.bestLabel, '4/2');
    });
    test('a player who has not batted has no highest', () {
      final s = PlayerStats.fromJson(_empty());
      expect(s.batting.highestLabel, '-');
      expect(s.bowling.bestLabel, '-');
      expect(s.isEmpty, isTrue);
    });
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('renders all stat panels on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, _rich());
        expect(tester.takeException(), isNull);
        // header
        expect(find.text('Rahul'), findsWidgets);
        expect(find.textContaining('5 matches'), findsOneWidget);
        // batting card
        expect(find.byKey(const Key('stats_batting')), findsOneWidget);
        expect(find.text('80'), findsWidgets); // runs
        expect(find.text('50*'), findsOneWidget); // HS not out
        expect(find.text('80.00'), findsOneWidget); // average
        // bowling card
        expect(find.byKey(const Key('stats_bowling')), findsOneWidget);
        expect(find.text('4/2'), findsOneWidget); // BBI
        expect(find.text('6'), findsWidgets); // wickets
        // fielding line
        expect(find.byKey(const Key('stats_fielding')), findsOneWidget);
        // form strip is below the fold - scroll to it
        await tester.scrollUntilVisible(
          find.byKey(const Key('stats_form')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const Key('stats_form')), findsOneWidget);
        expect(find.text('12*'), findsOneWidget); // a not-out match -> star
        expect(find.text('2w'), findsOneWidget); // bowled 2 in a match
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('undefined ratios show "-" on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, _undefinedRatios());
        expect(tester.takeException(), isNull);
        // batting average (0 dismissals) AND bowling avg/SR (0 wickets) are '-'.
        expect(find.text('-'), findsWidgets);
        // but defined ratios still show (batting SR + economy)
        expect(find.text('160.00'), findsOneWidget);
        expect(find.text('7.00'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('empty state when no completed matches on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, _empty());
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('stats_empty')), findsOneWidget);
        // the cards are hidden when there is nothing to show
        expect(find.byKey(const Key('stats_batting')), findsNothing);
        expect(find.byKey(const Key('stats_form')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
