/// Typed view of the `tournament_overview` RPC jsonb. Parsing + display
/// formatting (NRR sign, status labels, fixture result lines, qualified markers)
/// lives here so it can be unit-tested without the widget tree.
library;

num? _num(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse(v.toString()));

int _int(dynamic v) => _num(v)?.toInt() ?? 0;

String tournamentStatusLabel(String? status) => switch (status) {
      'setup' => 'Setup',
      'group_stage' => 'Group stage',
      'playoffs' => 'Playoffs',
      'complete' => 'Complete',
      _ => status ?? '',
    };

/// NRR with an explicit sign, or '-' when undefined.
String nrrLabel(num? nrr) =>
    nrr == null ? '-' : '${nrr >= 0 ? '+' : ''}${nrr.toStringAsFixed(2)}';

class TournamentInfo {
  TournamentInfo({
    required this.id,
    required this.name,
    required this.status,
    required this.oversLimit,
    required this.groupCount,
    required this.qualifiersPerGroup,
    this.ballType,
    this.championTeamId,
    this.city,
    this.venue,
  });

  final String id;
  final String name;
  final String status;
  final int oversLimit;
  final int groupCount;
  final int qualifiersPerGroup;
  final String? ballType;
  final String? championTeamId;
  final String? city;
  final String? venue;

  String get statusLabel => tournamentStatusLabel(status);
  bool get isComplete => status == 'complete';

  factory TournamentInfo.fromJson(Map<String, dynamic> j) => TournamentInfo(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Tournament',
        status: (j['status'] as String?) ?? 'setup',
        oversLimit: _int(j['overs_limit']),
        groupCount: _int(j['group_count']),
        qualifiersPerGroup: _int(j['qualifiers_per_group']),
        ballType: j['ball_type'] as String?,
        championTeamId: j['champion_team_id'] as String?,
        city: j['city'] as String?,
        venue: j['venue'] as String?,
      );
}

class StandingRow {
  StandingRow({
    required this.teamId,
    required this.name,
    required this.played,
    required this.won,
    required this.lost,
    required this.tied,
    required this.noResult,
    required this.points,
    required this.nrr,
  });

  final String teamId;
  final String name;
  final int played;
  final int won;
  final int lost;
  final int tied;
  final int noResult;
  final int points;
  final num? nrr;

  String get nrrText => nrrLabel(nrr);

  factory StandingRow.fromJson(Map<String, dynamic> j) => StandingRow(
        teamId: j['team_id'] as String,
        name: (j['name'] as String?) ?? 'Team',
        played: _int(j['played']),
        won: _int(j['won']),
        lost: _int(j['lost']),
        tied: _int(j['tied']),
        noResult: _int(j['no_result']),
        points: _int(j['points']),
        nrr: _num(j['nrr']),
      );
}

class StandingsGroup {
  StandingsGroup({required this.label, required this.rows});

  final String label;
  final List<StandingRow> rows;

  factory StandingsGroup.fromJson(Map<String, dynamic> j) => StandingsGroup(
        label: (j['group_label'] as String?) ?? '',
        rows: ((j['rows'] as List?) ?? const [])
            .map((e) => StandingRow.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class Fixture {
  Fixture({
    required this.matchId,
    required this.stage,
    required this.teamA,
    required this.teamB,
    required this.status,
    this.teamAId,
    this.teamBId,
    this.groupLabel,
    this.bracketSlot,
    this.result,
    this.scheduledAt,
    this.venue,
    this.innings = const [],
  });

  final String matchId;
  final String stage; // group | semifinal | final
  final String teamA;
  final String teamB;
  final String? teamAId;
  final String? teamBId;
  final String status; // setup | live | innings_break | complete | abandoned
  final String? groupLabel;
  final String? bracketSlot;
  final Map<String, dynamic>? result;
  final DateTime? scheduledAt; // TOUR-4
  final String? venue; // TOUR-4
  // Each: {innings_number, batting_team_id, runs, wickets} (TOUR-6).
  final List<Map<String, dynamic>> innings;

  /// TOUR-4: "Sun 20 Jul, 10:00 - Shivaji Park" (either part optional).
  String get scheduleLine {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dt = scheduledAt?.toLocal();
    final when = dt == null
        ? ''
        : '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]}, '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return [
      if (when.isNotEmpty) when,
      if (venue?.isNotEmpty ?? false) venue!,
    ].join(' - ');
  }

  bool get isLive => status == 'live' || status == 'innings_break';
  bool get isComplete => status == 'complete' || status == 'abandoned';
  bool get isUpcoming => status == 'setup';

  String get stageLabel => switch (stage) {
        'group' => groupLabel != null ? 'Group $groupLabel' : 'Group',
        'semifinal' => 'Semifinal',
        'final' => 'Final',
        _ => stage,
      };

  /// "152/6" for the team that batted with [teamId], or null if it has no innings.
  String? _scoreFor(String? teamId) {
    if (teamId == null) return null;
    for (final i in innings) {
      if (i['batting_team_id'] == teamId) {
        return '${i['runs'] ?? 0}/${i['wickets'] ?? 0}';
      }
    }
    return null;
  }

  /// A short result/status line for the fixtures list. For a completed match it
  /// shows the actual scoreline + winner (TOUR-6), e.g. "Mumbai 152/6 beat
  /// Chennai 134/9"; live/upcoming stay simple.
  String get statusLine {
    if (isLive) return 'Live';
    if (isUpcoming) return 'Upcoming';
    final r = result;
    final aScore = _scoreFor(teamAId);
    final bScore = _scoreFor(teamBId);
    final winnerId = r?['winner_team_id'] as String?;
    final type = r?['result_type'] as String?;
    if (aScore != null && bScore != null) {
      if (winnerId == teamAId) return '$teamA $aScore beat $teamB $bScore';
      if (winnerId == teamBId) return '$teamB $bScore beat $teamA $aScore';
      if (type == 'tie' || type == 'tie_superover') {
        return '$teamA $aScore tied $teamB $bScore';
      }
      return '$teamA $aScore, $teamB $bScore';
    }
    // No innings scores (e.g. abandoned before play): fall back to the note/type.
    final note = r?['note'] as String?;
    if (note != null && note.isNotEmpty) return note;
    return switch (type) {
      'tie' || 'tie_superover' => 'Tied',
      'no_result' => 'No result',
      'abandoned' => 'Abandoned',
      _ => 'Completed',
    };
  }

  static String statusLabelFor(String s) => switch (s) {
        'complete' => 'Completed',
        'abandoned' => 'Abandoned',
        _ => s,
      };

  factory Fixture.fromJson(Map<String, dynamic> j) => Fixture(
        matchId: j['match_id'] as String,
        stage: (j['stage'] as String?) ?? 'group',
        // an unresolved side is TBD, never a fake-looking "Team A"
        teamA: (j['team_a'] as String?) ?? 'TBD',
        teamB: (j['team_b'] as String?) ?? 'TBD',
        teamAId: j['team_a_id'] as String?,
        teamBId: j['team_b_id'] as String?,
        status: (j['status'] as String?) ?? 'setup',
        groupLabel: j['group_label'] as String?,
        bracketSlot: j['bracket_slot'] as String?,
        result: (j['result'] as Map?)?.cast<String, dynamic>(),
        scheduledAt: DateTime.tryParse(j['scheduled_at']?.toString() ?? ''),
        venue: j['venue'] as String?,
        innings: [
          for (final i in (j['innings'] as List? ?? const []))
            (i as Map).cast<String, dynamic>(),
        ],
      );
}

class LeaderEntry {
  LeaderEntry({
    required this.memberId,
    required this.name,
    required this.value,
    this.profileId,
  });

  final String memberId;
  final String name;
  final int value;
  // Null for unclaimed guests; when set, the row links to /player/:profileId.
  final String? profileId;

  factory LeaderEntry.fromJson(Map<String, dynamic> j, String valueKey) =>
      LeaderEntry(
        memberId: (j['member_id'] as String?) ?? '',
        name: (j['name'] as String?) ?? 'Player',
        value: _int(j[valueKey]),
        profileId: j['profile_id'] as String?,
      );
}

class Leaderboard {
  Leaderboard({
    required this.mostRuns,
    required this.mostWickets,
    required this.mostCatches,
    required this.mostFours,
    required this.mostSixes,
  });

  final List<LeaderEntry> mostRuns;
  final List<LeaderEntry> mostWickets;
  final List<LeaderEntry> mostCatches;
  final List<LeaderEntry> mostFours;
  final List<LeaderEntry> mostSixes;

  static List<LeaderEntry> _list(dynamic v, String key) =>
      ((v as List?) ?? const [])
          .map((e) => LeaderEntry.fromJson((e as Map).cast<String, dynamic>(), key))
          .toList();

  factory Leaderboard.fromJson(Map<String, dynamic> j) => Leaderboard(
        mostRuns: _list(j['most_runs'], 'runs'),
        mostWickets: _list(j['most_wickets'], 'wickets'),
        mostCatches: _list(j['most_catches'], 'dismissals'),
        mostFours: _list(j['most_fours'], 'fours'),
        mostSixes: _list(j['most_sixes'], 'sixes'),
      );
}

class TournamentTeamRef {
  TournamentTeamRef({required this.teamId, required this.name, required this.groupLabel});

  final String teamId;
  final String name;
  final String groupLabel;

  factory TournamentTeamRef.fromJson(Map<String, dynamic> j) => TournamentTeamRef(
        teamId: j['team_id'] as String,
        name: (j['name'] as String?) ?? 'Team',
        groupLabel: (j['group_label'] as String?) ?? 'A',
      );
}

class TournamentOverview {
  TournamentOverview({
    required this.info,
    required this.teams,
    required this.standings,
    required this.fixtures,
    required this.leaderboard,
    required this.championTeamId,
  });

  final TournamentInfo info;
  final List<TournamentTeamRef> teams;
  final List<StandingsGroup> standings;
  final List<Fixture> fixtures;
  final Leaderboard leaderboard;
  final String? championTeamId;

  List<Fixture> fixturesForStage(String stage) =>
      fixtures.where((f) => f.stage == stage).toList();

  factory TournamentOverview.fromJson(Map<String, dynamic> j) {
    final standings =
        (j['standings'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TournamentOverview(
      info: TournamentInfo.fromJson(
          (j['tournament'] as Map).cast<String, dynamic>()),
      teams: ((j['teams'] as List?) ?? const [])
          .map((e) => TournamentTeamRef.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      standings: ((standings['groups'] as List?) ?? const [])
          .map((e) => StandingsGroup.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      fixtures: ((j['fixtures'] as List?) ?? const [])
          .map((e) => Fixture.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      leaderboard: Leaderboard.fromJson(
          (j['leaderboard'] as Map?)?.cast<String, dynamic>() ?? const {}),
      championTeamId: j['champion_team_id'] as String?,
    );
  }
}
