import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/tournaments/data/tournament_models.dart';
import 'package:pitch_app/src/features/tournaments/data/tournament_providers.dart';
import 'package:pitch_app/src/features/tournaments/presentation/manage_tournament_screen.dart';
import 'package:pitch_app/src/features/tournaments/presentation/tournament_page_screen.dart';

Map<String, dynamic> _completeOverview() => {
      'tournament': {'id': 't1', 'name': 'Mumbai Premier League', 'status': 'complete',
        'overs_limit': 20, 'group_count': 2, 'qualifiers_per_group': 2,
        'champion_team_id': 'dadar', 'city': 'Mumbai'},
      'teams': [
        {'team_id': 'dadar', 'name': 'Dadar Dynamos', 'group_label': 'A'},
        {'team_id': 'colaba', 'name': 'Colaba Kings', 'group_label': 'A'},
      ],
      'standings': {'groups': [
        {'group_label': 'A', 'rows': [
          {'team_id': 'dadar', 'name': 'Dadar Dynamos', 'played': 1, 'won': 1, 'lost': 0,
           'tied': 0, 'no_result': 0, 'points': 2, 'nrr': 1.82},
          {'team_id': 'colaba', 'name': 'Colaba Kings', 'played': 1, 'won': 0, 'lost': 1,
           'tied': 0, 'no_result': 0, 'points': 0, 'nrr': -2.10},
        ]},
      ]},
      'fixtures': [
        {'match_id': 'g1', 'stage': 'group', 'group_label': 'A', 'team_a': 'Dadar Dynamos',
         'team_b': 'Colaba Kings', 'status': 'complete', 'result': {'result_type': 'win_by_runs', 'winner_team_id': 'dadar'}},
        {'match_id': 's1', 'stage': 'semifinal', 'bracket_slot': 'SF1', 'team_a': 'Dadar Dynamos',
         'team_b': 'Sion Strikers', 'status': 'complete', 'result': {'result_type': 'win_by_runs', 'winner_team_id': 'dadar'}},
        {'match_id': 'f1', 'stage': 'final', 'bracket_slot': 'F', 'team_a': 'Dadar Dynamos',
         'team_b': 'Bandra Blasters', 'status': 'complete', 'result': {'result_type': 'win_by_runs', 'winner_team_id': 'dadar'}},
      ],
      'leaderboard': {
        'most_runs': [{'member_id': 'rohit', 'name': 'Rohit S.', 'runs': 182}],
        'most_wickets': [], 'most_catches': [], 'most_fours': [], 'most_sixes': [],
      },
      'champion_team_id': 'dadar',
    };

Map<String, dynamic> _stateOverview(String status, List fixtures, List teams) => {
      'tournament': {'id': 't1', 'name': 'Cup', 'status': status, 'overs_limit': 20,
        'group_count': 2, 'qualifiers_per_group': 2},
      'teams': teams,
      'standings': {'groups': []},
      'fixtures': fixtures,
      'leaderboard': {},
    };

Future<void> _pumpPage(WidgetTester t, Map<String, dynamic> ov) async {
  await t.pumpWidget(ProviderScope(overrides: [
    tournamentOverviewProvider.overrideWith((ref, id) async => TournamentOverview.fromJson(ov)),
  ], child: const MaterialApp(home: TournamentPageScreen(tournamentId: 't1'))));
  await t.pumpAndSettle();
}

Future<void> _pumpManage(WidgetTester t, Map<String, dynamic> ov) async {
  await t.pumpWidget(ProviderScope(overrides: [
    tournamentOverviewProvider.overrideWith((ref, id) async => TournamentOverview.fromJson(ov)),
  ], child: const MaterialApp(home: ManageTournamentScreen(tournamentId: 't1'))));
  await t.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('public page: 4 tabs + champion banner on $platform', (t) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpPage(t, _completeOverview());
        expect(t.takeException(), isNull);
        // champion banner
        expect(find.textContaining('Champions: Dadar Dynamos'), findsOneWidget);
        // Table tab (default): NRR is visible
        expect(find.text('+1.82'), findsOneWidget);
        expect(find.text('-2.10'), findsOneWidget);
        // Fixtures
        await t.tap(find.text('Fixtures'));
        await t.pumpAndSettle();
        expect(find.text('Semifinals'), findsOneWidget);
        // Bracket
        await t.tap(find.text('Bracket'));
        await t.pumpAndSettle();
        expect(find.text('Final'), findsWidgets);
        // Leaders
        await t.tap(find.text('Leaders'));
        await t.pumpAndSettle();
        expect(find.widgetWithText(ChoiceChip, 'Runs'), findsOneWidget);
        expect(find.text('Rohit S.'), findsOneWidget);
        expect(find.text('182'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('manage: setup offers generate fixtures on $platform', (t) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpManage(t, _stateOverview('setup', [], [
          {'team_id': 'a1', 'name': 'A1', 'group_label': 'A'},
          {'team_id': 'a2', 'name': 'A2', 'group_label': 'A'},
          {'team_id': 'b1', 'name': 'B1', 'group_label': 'B'},
          {'team_id': 'b2', 'name': 'B2', 'group_label': 'B'},
        ]));
        expect(t.takeException(), isNull);
        expect(find.widgetWithText(FilledButton, 'Generate group fixtures'), findsOneWidget);
        final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate group fixtures'));
        expect(btn.onPressed, isNotNull); // enabled (2 per group)
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('manage: group stage offers generate playoffs when done on $platform', (t) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpManage(t, _stateOverview('group_stage', [
          {'match_id': 'g1', 'stage': 'group', 'group_label': 'A', 'team_a': 'A1', 'team_b': 'A2', 'status': 'complete', 'result': null},
          {'match_id': 'g2', 'stage': 'group', 'group_label': 'B', 'team_a': 'B1', 'team_b': 'B2', 'status': 'complete', 'result': null},
        ], []));
        expect(t.takeException(), isNull);
        final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate playoffs'));
        expect(btn.onPressed, isNotNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('manage: playoffs offers advance on $platform', (t) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpManage(t, _stateOverview('playoffs', [
          {'match_id': 's1', 'stage': 'semifinal', 'bracket_slot': 'SF1', 'team_a': 'A1', 'team_b': 'B2', 'status': 'complete', 'result': null},
          {'match_id': 's2', 'stage': 'semifinal', 'bracket_slot': 'SF2', 'team_a': 'B1', 'team_b': 'A2', 'status': 'complete', 'result': null},
        ], []));
        expect(t.takeException(), isNull);
        expect(find.widgetWithText(FilledButton, 'Advance to final'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
