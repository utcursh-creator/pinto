/// View models for the player stats screen, parsed from the
/// `player_public_profile` RPC jsonb. The formatting logic (undefined ratios
/// render as '-', a not-out high score as `50*`, BBI as `W/R`) lives here so it
/// can be unit-tested independently of the widget tree.
library;

num? _num(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse(v.toString()));

int _int(dynamic v) => _num(v)?.toInt() ?? 0;

/// Formats a 2-decimal ratio, or '-' when undefined (the backend returns null
/// for div-by-zero ratios like average with zero dismissals).
String fmtRatio(num? v) => v == null ? '-' : v.toStringAsFixed(2);

class PlayerIdentity {
  PlayerIdentity({required this.displayName, this.photoUrl, this.battingStyle});

  final String displayName;
  final String? photoUrl;
  final String? battingStyle;

  factory PlayerIdentity.fromJson(Map<String, dynamic>? j) => PlayerIdentity(
        displayName: (j?['display_name'] as String?) ?? 'Player',
        photoUrl: j?['photo_url'] as String?,
        battingStyle: j?['batting_style'] as String?,
      );
}

class BattingCard {
  BattingCard({
    required this.innings,
    required this.notOuts,
    required this.runs,
    required this.balls,
    required this.highest,
    required this.highestNotOut,
    required this.average,
    required this.strikeRate,
    required this.fours,
    required this.sixes,
    required this.fifties,
    required this.hundreds,
    required this.ducks,
  });

  final int innings;
  final int notOuts;
  final int runs;
  final int balls;
  final int? highest;
  final bool highestNotOut;
  final num? average;
  final num? strikeRate;
  final int fours;
  final int sixes;
  final int fifties;
  final int hundreds;
  final int ducks;

  /// Highest score, with a `*` suffix when it was a not-out, or '-' when the
  /// player has not batted.
  String get highestLabel =>
      highest == null ? '-' : '$highest${highestNotOut ? '*' : ''}';

  factory BattingCard.fromJson(Map<String, dynamic> j) => BattingCard(
        innings: _int(j['innings']),
        notOuts: _int(j['not_outs']),
        runs: _int(j['runs']),
        balls: _int(j['balls']),
        highest: _num(j['highest'])?.toInt(),
        highestNotOut: (j['highest_not_out'] as bool?) ?? false,
        average: _num(j['average']),
        strikeRate: _num(j['strike_rate']),
        fours: _int(j['fours']),
        sixes: _int(j['sixes']),
        fifties: _int(j['fifties']),
        hundreds: _int(j['hundreds']),
        ducks: _int(j['ducks']),
      );
}

class BowlingCard {
  BowlingCard({
    required this.innings,
    required this.overs,
    required this.balls,
    required this.runs,
    required this.wickets,
    required this.maidens,
    required this.bestWickets,
    required this.bestRuns,
    required this.average,
    required this.economy,
    required this.strikeRate,
    required this.fourWickets,
    required this.fiveWickets,
  });

  final int innings;
  final String overs;
  final int balls;
  final int runs;
  final int wickets;
  final int maidens;
  final int? bestWickets;
  final int? bestRuns;
  final num? average;
  final num? economy;
  final num? strikeRate;
  final int fourWickets;
  final int fiveWickets;

  /// Best bowling in an innings as `W/R`, or '-' when the player has not bowled.
  String get bestLabel =>
      bestWickets == null ? '-' : '$bestWickets/$bestRuns';

  factory BowlingCard.fromJson(Map<String, dynamic> j) => BowlingCard(
        innings: _int(j['innings']),
        overs: (j['overs'] as String?) ?? '0.0',
        balls: _int(j['balls']),
        runs: _int(j['runs']),
        wickets: _int(j['wickets']),
        maidens: _int(j['maidens']),
        bestWickets: _num(j['best_wickets'])?.toInt(),
        bestRuns: _num(j['best_runs'])?.toInt(),
        average: _num(j['average']),
        economy: _num(j['economy']),
        strikeRate: _num(j['strike_rate']),
        fourWickets: _int(j['four_wickets']),
        fiveWickets: _int(j['five_wickets']),
      );
}

class FieldingLine {
  FieldingLine({
    required this.catches,
    required this.runOuts,
    required this.stumpings,
  });

  final int catches;
  final int runOuts;
  final int stumpings;

  bool get isEmpty => catches == 0 && runOuts == 0 && stumpings == 0;

  factory FieldingLine.fromJson(Map<String, dynamic> j) => FieldingLine(
        catches: _int(j['catches']),
        runOuts: _int(j['run_outs']),
        stumpings: _int(j['stumpings']),
      );
}

/// One match in the last-N form strip (batting + bowling collapsed per match).
class FormEntry {
  FormEntry({
    required this.matchId,
    required this.runs,
    required this.balls,
    required this.out,
    required this.wickets,
    required this.runsConceded,
  });

  final String matchId;
  final int runs;
  final int balls;
  final bool out;
  final int wickets;
  final int runsConceded;

  /// Batting figure, e.g. `30` or `30*` (not out). A player who never faced a
  /// ball and wasn't dismissed did not bat (STAT-3) - show "DNB", not "0*".
  String get batLabel =>
      balls == 0 && !out ? 'DNB' : '$runs${out ? '' : '*'}';

  factory FormEntry.fromJson(Map<String, dynamic> j) {
    final bat = (j['bat'] as Map?)?.cast<String, dynamic>() ?? const {};
    final bowl = (j['bowl'] as Map?)?.cast<String, dynamic>() ?? const {};
    return FormEntry(
      matchId: (j['match_id'] as String?) ?? '',
      runs: _int(bat['runs']),
      balls: _int(bat['balls']),
      out: (bat['out'] as bool?) ?? false,
      wickets: _int(bowl['wickets']),
      runsConceded: _int(bowl['runs_conceded']),
    );
  }
}

class PlayerStats {
  PlayerStats({
    required this.identity,
    required this.matches,
    required this.batting,
    required this.bowling,
    required this.fielding,
    required this.recentForm,
  });

  final PlayerIdentity identity;
  final int matches;
  final BattingCard batting;
  final BowlingCard bowling;
  final FieldingLine fielding;
  final List<FormEntry> recentForm;

  /// True when the player has no completed-match history to show.
  bool get isEmpty =>
      matches == 0 && batting.innings == 0 && bowling.innings == 0;

  factory PlayerStats.fromJson(Map<String, dynamic> j) {
    final career = (j['career'] as Map?)?.cast<String, dynamic>() ?? const {};
    final batting =
        (career['batting'] as Map?)?.cast<String, dynamic>() ?? const {};
    final bowling =
        (career['bowling'] as Map?)?.cast<String, dynamic>() ?? const {};
    final fielding =
        (career['fielding'] as Map?)?.cast<String, dynamic>() ?? const {};
    final form = (j['recent_form'] as List?) ?? const [];
    return PlayerStats(
      identity:
          PlayerIdentity.fromJson((j['profile'] as Map?)?.cast<String, dynamic>()),
      matches: _int(career['matches']),
      batting: BattingCard.fromJson(batting),
      bowling: BowlingCard.fromJson(bowling),
      fielding: FieldingLine.fromJson(fielding),
      recentForm: form
          .map((e) => FormEntry.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}
