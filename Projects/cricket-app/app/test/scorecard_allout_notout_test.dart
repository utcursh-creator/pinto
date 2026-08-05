import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_viewer_screen.dart';

/// Review #3 (MEDIUM): on every all-out innings the public scorecard marks the
/// LAST batter dismissed as not out.
///
/// The batting card put a ' *' beside any row whose batter_id matched
/// striker_id or non_striker_id. That reads striker_id as "at the crease", and
/// it is not: record_ball permits a null incoming batter on the final wicket
/// (there is nobody left to come in), so compute_innings_state leaves the
/// dismissed batter sitting in _striker. Verified on the live DB - after the
/// last wicket, innings_status='completed' and striker_id is the very batter
/// compute_innings_cards reports as dismissed='bowled'.
///
/// So a login-free `/watch/<id>` scorecard - the share target - showed TWO
/// not-out batters on an innings that lost every wicket, and the
/// fall-of-wickets block three rows below named one of them as dismissed. The
/// card contradicted itself, in public.
///
/// The not-out truth is already in the payload: fall_of_wickets carries
/// dismissed_player_id, and a `retired_not_out` deliberately gets NO entry
/// there (compute_innings_state's retirement branch only appends to _fow when
/// the type is a real dismissal). So "at the crease AND not in that set" is
/// exactly the asterisk.
const _out1 = 's1';
const _out2 = 's2';
const _lastOut = 's3';
const _stranded = 's4';

/// A completed, ALL-OUT innings of a 4-player squad. The last wicket had no
/// incoming batter, so the fold still names the dismissed batter as striker.
Map<String, dynamic> _allOutFold() => {
      'runs': 40,
      'wickets': 3,
      'legal_balls': 42,
      'over': '7.0',
      'extras': {'wides': 1, 'no_balls': 0, 'byes': 0, 'leg_byes': 0, 'penalty': 0},
      // THE BUG'S SOURCE: s3 was bowled and never replaced.
      'striker_id': _lastOut,
      'non_striker_id': _stranded,
      'free_hit_active': false,
      'batting': [
        {'batter_id': _out1, 'runs': 18, 'balls': 14, 'fours': 2, 'sixes': 0},
        {'batter_id': _out2, 'runs': 9, 'balls': 11, 'fours': 1, 'sixes': 0},
        {'batter_id': _lastOut, 'runs': 7, 'balls': 9, 'fours': 0, 'sixes': 0},
        {'batter_id': _stranded, 'runs': 5, 'balls': 8, 'fours': 0, 'sixes': 0},
      ],
      'bowling': [
        {
          'bowler_id': 'b1',
          'legal_balls': 42,
          'runs_conceded': 40,
          'maidens': 0,
          'dots': 14,
          'wides_bowled': 1,
          'no_balls_bowled': 0,
          'wickets': 3,
          'overs': '7.0',
          'economy': 5.71,
        },
      ],
      'fall_of_wickets': [
        {'wicket_number': 1, 'score_at_fall': 18, 'over': '3.1', 'dismissed_player_id': _out1},
        {'wicket_number': 2, 'score_at_fall': 30, 'over': '5.4', 'dismissed_player_id': _out2},
        {'wicket_number': 3, 'score_at_fall': 40, 'over': '7.0', 'dismissed_player_id': _lastOut},
      ],
      'partnerships': [],
      'current_partnership': null,
      'per_over': [],
      'worm': [],
      'did_not_bat': [],
      'crr': 5.71,
      'rrr': null,
      'runs_required': null,
      'balls_remaining': 78,
      'wickets_remaining': 0,
      'innings_status': 'completed',
      'result': null,
      'orphaned_deliveries': [],
    };

Future<void> _pumpScorecard(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchProvider.overrideWith((ref, id) async => {
              'id': 'm1',
              'team_a_id': 'A',
              'team_b_id': 'B',
              'venue': 'Shivaji Park',
              'overs_limit': 20,
              'balls_per_over': 6,
              'status': 'completed',
              'toss_winner_id': 'A',
              'toss_decision': 'bat',
            }),
        matchTeamNamesProvider.overrideWith(
            (ref, id) async => {'A': 'Mumbai United', 'B': 'Dadar CC'}),
        matchInningsListProvider.overrideWith((ref, id) async => [
              {
                'id': 'in1',
                'innings_number': 1,
                'batting_team_id': 'A',
                'bowling_team_id': 'B',
                'status': 'completed',
                'target': null,
              },
            ]),
        matchSquadProvider.overrideWith((ref, id) async => [
              {'team_id': 'A', 'team_member_id': _out1, 'team_members': {'guest_name': 'Rahul', 'profiles': null}},
              {'team_id': 'A', 'team_member_id': _out2, 'team_members': {'guest_name': 'Arjun', 'profiles': null}},
              {'team_id': 'A', 'team_member_id': _lastOut, 'team_members': {'guest_name': 'Sachin', 'profiles': null}},
              {'team_id': 'A', 'team_member_id': _stranded, 'team_members': {'guest_name': 'Vinod', 'profiles': null}},
              {'team_id': 'B', 'team_member_id': 'b1', 'team_members': {'guest_name': 'Imran', 'profiles': null}},
            ]),
        inningsStateProvider.overrideWith((ref, id) async => _allOutFold()),
        inningsWagonProvider.overrideWith((ref, id) async => const []),
      ],
      child: const MaterialApp(
        home: MatchViewerScreen(matchId: 'm1', enableRealtime: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scorecard'));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('an all-out innings shows exactly ONE not-out batter on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpScorecard(tester);
        expect(tester.takeException(), isNull);

        expect(find.text('Sachin  *'), findsNothing,
            reason: 'Sachin was bowled - the fall-of-wickets block on this very '
                'screen says so. He is only still in striker_id because there '
                'was no incoming batter left to replace him');
        expect(find.text('Sachin'), findsOneWidget,
            reason: 'and he must still appear on the card, just without the '
                'not-out mark');
        expect(find.text('Vinod  *'), findsOneWidget,
            reason: 'the stranded partner IS not out - an all-out innings has '
                'exactly one, and removing the wrong asterisk must not remove '
                'the right one');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: mid-innings, both batters at the crease keep their '
        'asterisk on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchProvider.overrideWith((ref, id) async => {
                    'id': 'm1',
                    'team_a_id': 'A',
                    'team_b_id': 'B',
                    'overs_limit': 20,
                    'balls_per_over': 6,
                    'status': 'live',
                    'toss_winner_id': 'A',
                    'toss_decision': 'bat',
                  }),
              matchTeamNamesProvider.overrideWith(
                  (ref, id) async => {'A': 'Mumbai United', 'B': 'Dadar CC'}),
              matchInningsListProvider.overrideWith((ref, id) async => [
                    {
                      'id': 'in1',
                      'innings_number': 1,
                      'batting_team_id': 'A',
                      'bowling_team_id': 'B',
                      'status': 'in_progress',
                      'target': null,
                    },
                  ]),
              matchSquadProvider.overrideWith((ref, id) async => [
                    {'team_id': 'A', 'team_member_id': _out1, 'team_members': {'guest_name': 'Rahul', 'profiles': null}},
                    {'team_id': 'A', 'team_member_id': _lastOut, 'team_members': {'guest_name': 'Sachin', 'profiles': null}},
                    {'team_id': 'A', 'team_member_id': _stranded, 'team_members': {'guest_name': 'Vinod', 'profiles': null}},
                    {'team_id': 'B', 'team_member_id': 'b1', 'team_members': {'guest_name': 'Imran', 'profiles': null}},
                  ]),
              inningsStateProvider.overrideWith((ref, id) async {
                final f = _allOutFold();
                // one wicket down, and the pair at the crease are both live
                f['wickets'] = 1;
                f['wickets_remaining'] = 2;
                f['innings_status'] = 'in_progress';
                f['striker_id'] = _lastOut;
                f['non_striker_id'] = _stranded;
                f['fall_of_wickets'] = [
                  {'wicket_number': 1, 'score_at_fall': 18, 'over': '3.1',
                    'dismissed_player_id': _out1},
                ];
                return f;
              }),
              inningsWagonProvider.overrideWith((ref, id) async => const []),
            ],
            child: const MaterialApp(
              home: MatchViewerScreen(matchId: 'm1', enableRealtime: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Scorecard'));
        await tester.pumpAndSettle();

        expect(find.text('Sachin  *'), findsOneWidget);
        expect(find.text('Vinod  *'), findsOneWidget,
            reason: 'nobody at the crease has been dismissed, so both carry '
                'the not-out mark exactly as before');
        expect(find.text('Rahul  *'), findsNothing,
            reason: 'and the batter who IS out still carries none');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
