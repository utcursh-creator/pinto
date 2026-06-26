import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/tournaments/data/tournament_models.dart';

Map<String, dynamic> _overview() => {
      'tournament': {
        'id': 't1', 'name': 'Mumbai Premier League', 'status': 'complete',
        'overs_limit': 20, 'balls_per_over': 6, 'ball_type': 'leather',
        'group_count': 2, 'qualifiers_per_group': 2, 'champion_team_id': 'dadar',
        'city': 'Mumbai', 'venue': 'Shivaji Park',
      },
      'teams': [
        {'team_id': 'dadar', 'name': 'Dadar Dynamos', 'group_label': 'A'},
      ],
      'standings': {
        'groups': [
          {'group_label': 'A', 'rows': [
            {'team_id': 'dadar', 'name': 'Dadar Dynamos', 'played': 3, 'won': 3,
             'lost': 0, 'tied': 0, 'no_result': 0, 'points': 6, 'nrr': 1.82},
            {'team_id': 'colaba', 'name': 'Colaba Kings', 'played': 3, 'won': 0,
             'lost': 3, 'tied': 0, 'no_result': 0, 'points': 0, 'nrr': -2.10},
          ]},
          {'group_label': 'B', 'rows': []},
        ],
      },
      'fixtures': [
        {'match_id': 'm1', 'stage': 'group', 'group_label': 'A', 'bracket_slot': null,
         'team_a': 'Dadar Dynamos', 'team_b': 'Colaba Kings', 'status': 'complete',
         'result': {'result_type': 'win_by_runs', 'winner_team_id': 'dadar'}},
        {'match_id': 'm2', 'stage': 'semifinal', 'group_label': null, 'bracket_slot': 'SF1',
         'team_a': 'Dadar Dynamos', 'team_b': 'Sion Strikers', 'status': 'live', 'result': null},
        {'match_id': 'm3', 'stage': 'final', 'group_label': null, 'bracket_slot': 'F',
         'team_a': 'Dadar Dynamos', 'team_b': 'Bandra Blasters', 'status': 'setup', 'result': null},
      ],
      'leaderboard': {
        'most_runs': [{'member_id': 'rohit', 'name': 'Rohit S.', 'runs': 182}],
        'most_wickets': [{'member_id': 'bumrah', 'name': 'J. Bumrah', 'wickets': 9}],
        'most_catches': [{'member_id': 'pant', 'name': 'R. Pant', 'dismissals': 5}],
        'most_fours': [{'member_id': 'rohit', 'name': 'Rohit S.', 'fours': 22}],
        'most_sixes': [{'member_id': 'rohit', 'name': 'Rohit S.', 'sixes': 11}],
      },
      'champion_team_id': 'dadar',
    };

void main() {
  test('nrrLabel signs and formats, or shows - when undefined', () {
    expect(nrrLabel(1.82), '+1.82');
    expect(nrrLabel(-2.1), '-2.10');
    expect(nrrLabel(0), '+0.00');
    expect(nrrLabel(null), '-');
  });

  test('status labels', () {
    expect(tournamentStatusLabel('group_stage'), 'Group stage');
    expect(tournamentStatusLabel('complete'), 'Complete');
  });

  test('overview parses tournament + champion', () {
    final o = TournamentOverview.fromJson(_overview());
    expect(o.info.name, 'Mumbai Premier League');
    expect(o.info.isComplete, isTrue);
    expect(o.info.qualifiersPerGroup, 2);
    expect(o.championTeamId, 'dadar');
  });

  test('standings rows parse with NRR text', () {
    final o = TournamentOverview.fromJson(_overview());
    expect(o.standings.length, 2);
    final a = o.standings.first;
    expect(a.label, 'A');
    expect(a.rows.first.points, 6);
    expect(a.rows.first.nrrText, '+1.82');
    expect(a.rows.last.nrrText, '-2.10');
  });

  test('fixtures parse with stage labels + live/complete flags', () {
    final o = TournamentOverview.fromJson(_overview());
    final byStage = {for (final f in o.fixtures) f.stage: f};
    expect(byStage['group']!.stageLabel, 'Group A');
    expect(byStage['group']!.isComplete, isTrue);
    expect(byStage['semifinal']!.isLive, isTrue);
    expect(byStage['semifinal']!.stageLabel, 'Semifinal');
    expect(byStage['final']!.isUpcoming, isTrue);
  });

  test('leaderboard parses each category with the right value key', () {
    final lb = TournamentOverview.fromJson(_overview()).leaderboard;
    expect(lb.mostRuns.first.name, 'Rohit S.');
    expect(lb.mostRuns.first.value, 182);
    expect(lb.mostWickets.first.value, 9);
    expect(lb.mostCatches.first.value, 5);
    expect(lb.mostSixes.first.value, 11);
  });
}
