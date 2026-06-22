import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/platform/platform.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../data/match_providers.dart';
import 'wagon_field.dart';

const _kInk = Color(0xFF0F2E26);
const _kTeal = Color(0xFF0F6E56);
const _kMint = Color(0xFF7DD3B9);

/// Read-only, login-free live match view (CricHeroes-style consume spine).
/// Tabs: Live / Scorecard / Charts / Info. Reads compute_innings_state for the
/// latest innings and re-folds on every `match:<id>` realtime broadcast.
class MatchViewerScreen extends ConsumerStatefulWidget {
  const MatchViewerScreen({
    required this.matchId,
    this.enableRealtime = true,
    super.key,
  });

  final String matchId;
  final bool enableRealtime;

  @override
  ConsumerState<MatchViewerScreen> createState() => _MatchViewerScreenState();
}

class _MatchViewerScreenState extends ConsumerState<MatchViewerScreen> {
  int _tab = 0;
  String? _scorecardInnings; // selected innings id for the scorecard
  RealtimeChannel? _channel;
  SupabaseClient? _client; // captured for safe teardown (ref is unsafe in dispose)
  List<String> _knownInnings = const [];

  @override
  void initState() {
    super.initState();
    if (widget.enableRealtime) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
    }
  }

  void _subscribe() {
    final c = ref.read(supabaseClientProvider);
    _client = c;
    // The match:<id> topic is public (authenticated + anon receive policy), but
    // the socket still needs a token: anon viewers were signed in anonymously.
    c.realtime.setAuth(c.auth.currentSession?.accessToken);
    final channel = c.channel('match:${widget.matchId}');
    for (final op in const ['INSERT', 'UPDATE', 'DELETE']) {
      channel.onBroadcast(event: op, callback: (_) => _refold());
    }
    channel.subscribe();
    _channel = channel;
  }

  void _refold() {
    if (!mounted) return;
    ref.invalidate(matchProvider(widget.matchId));
    ref.invalidate(matchInningsListProvider(widget.matchId));
    for (final id in _knownInnings) {
      ref.invalidate(inningsStateProvider(id));
    }
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) _client?.removeChannel(ch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(matchProvider(widget.matchId));
    final teams = ref.watch(matchTeamNamesProvider(widget.matchId));
    final innings = ref.watch(matchInningsListProvider(widget.matchId));
    final squad = ref.watch(matchSquadProvider(widget.matchId));

    final ready = match.hasValue && innings.hasValue && squad.hasValue;
    String title = 'Match';
    if (teams.hasValue && match.value != null) {
      final t = teams.value!;
      final a = t[match.value!['team_a_id']];
      final b = t[match.value!['team_b_id']];
      if (a != null && b != null) title = '$a v $b';
    }

    return AdaptiveScaffold(
      title: title,
      body: !ready
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _body(
              match.value!,
              teams.value ?? const {},
              innings.value ?? const [],
              squad.value ?? const [],
            ),
    );
  }

  Widget _body(
    Map<String, dynamic> match,
    Map<String, String> teams,
    List<Map<String, dynamic>> innings,
    List<Map<String, dynamic>> squad,
  ) {
    if (innings.isEmpty) {
      return const Center(child: Text('This match has not started yet.'));
    }
    _knownInnings = [for (final i in innings) i['id'] as String];
    final names = {
      for (final s in squad)
        s['team_member_id'] as String:
            memberName(s['team_members'] as Map<String, dynamic>),
    };
    final latest = innings.last;
    final scInnings = innings.firstWhere(
      (i) => i['id'] == _scorecardInnings,
      orElse: () => latest,
    );

    return Column(
      children: [
        _selector(),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _LiveTab(matchId: widget.matchId, match: match, innings: latest, teams: teams, names: names),
              _ScorecardTab(
                matchId: widget.matchId,
                innings: scInnings,
                allInnings: innings,
                teams: teams,
                names: names,
                onPickInnings: (id) => setState(() => _scorecardInnings = id),
              ),
              _ChartsTab(matchId: widget.matchId, innings: latest),
              _InfoTab(match: match, teams: teams),
            ],
          ),
        ),
      ],
    );
  }

  Widget _selector() {
    const labels = ['Live', 'Scorecard', 'Charts', 'Info'];
    if (isCupertino(context)) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: CupertinoSlidingSegmentedControl<int>(
          groupValue: _tab,
          children: {
            for (var i = 0; i < labels.length; i++)
              i: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(labels[i], style: const TextStyle(fontSize: 13)),
              ),
          },
          onValueChanged: (v) {
            if (v != null) setState(() => _tab = v);
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (var i = 0; i < labels.length; i++)
            ButtonSegment(value: i, label: Text(labels[i])),
        ],
        selected: {_tab},
        onSelectionChanged: (s) => setState(() => _tab = s.first),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

List<Map<String, dynamic>> _list(dynamic v) =>
    (v as List?)?.cast<Map<String, dynamic>>() ?? const [];

Map<String, dynamic>? _batter(List<Map<String, dynamic>> batting, String? id) {
  if (id == null) return null;
  for (final b in batting) {
    if (b['batter_id'] == id) return b;
  }
  return null;
}

String _sr(int runs, int balls) =>
    balls == 0 ? '-' : (runs * 100 / balls).toStringAsFixed(1);

// ---------------------------------------------------------------------------
// Live tab
// ---------------------------------------------------------------------------

class _LiveTab extends ConsumerWidget {
  const _LiveTab({
    required this.matchId,
    required this.match,
    required this.innings,
    required this.teams,
    required this.names,
  });

  final String matchId;
  final Map<String, dynamic> match;
  final Map<String, dynamic> innings;
  final Map<String, String> teams;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inningsStateProvider(innings['id'] as String));
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => Center(child: Text('Could not load score.\n$e')),
      data: (s) => _content(s),
    );
  }

  Widget _content(Map<String, dynamic> s) {
    final runs = _i(s['runs']);
    final wkts = _i(s['wickets']);
    final over = s['over']?.toString() ?? '0.0';
    final crr = s['crr'];
    final battingTeam = teams[innings['batting_team_id']] ?? 'Batting';
    final batting = _list(s['batting']);
    final strikerId = s['striker_id'] as String?;
    final nonStrikerId = s['non_striker_id'] as String?;
    final target = innings['target'] as int?;
    final live = match['status'] == 'live' &&
        s['innings_status'] == 'in_progress';
    final freeHit = s['free_hit_active'] == true;
    final perOver = _list(s['per_over']);
    final fow = _list(s['fall_of_wickets']);
    final cp = s['current_partnership'] as Map<String, dynamic>?;

    Widget batterRow(String? id, bool onStrike) {
      final b = _batter(batting, id);
      final r = _i(b?['runs']);
      final balls = _i(b?['balls']);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${names[id] ?? '-'}${onStrike ? '  *' : ''}',
                style: TextStyle(
                  fontWeight: onStrike ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Text('$r ($balls)', style: const TextStyle(fontFeatures: [])),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          width: double.infinity,
          color: _kInk,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    battingTeam,
                    style: const TextStyle(color: _kMint, fontSize: 15),
                  ),
                  if (live) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7263D),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$runs/$wkts',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Over $over'
                '${crr != null ? '   -   CRR $crr' : ''}',
                style: const TextStyle(color: _kMint),
              ),
              if (target != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Need ${_i(s['runs_required'])} off ${_i(s['balls_remaining'])}'
                    '${s['rrr'] != null ? '   -   RRR ${s['rrr']}' : ''}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
        if (freeHit)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF3D6),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: const Text(
              'FREE HIT',
              style: TextStyle(
                color: Color(0xFF8A6D00),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Column(
            children: [
              batterRow(strikerId, true),
              batterRow(nonStrikerId, false),
            ],
          ),
        ),
        if (cp != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                const Expanded(child: Text('Partnership')),
                Text('${_i(cp['runs'])} (${_i(cp['balls'])})'),
              ],
            ),
          ),
        const Divider(height: 24),
        if (perOver.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent overs', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 4),
                for (final o in perOver.reversed.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      'Over ${_i(o['over_number'])}:  ${_i(o['runs_in_over'])} runs'
                      '${_i(o['wickets_in_over']) > 0 ? ', ${_i(o['wickets_in_over'])} wkt' : ''}',
                    ),
                  ),
              ],
            ),
          ),
        if (fow.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Text(
              'Last wicket: ${names[fow.last['dismissed_player_id']] ?? '-'}'
              ' at ${_i(fow.last['score_at_fall'])}/${_i(fow.last['wicket_number'])}'
              ' (${fow.last['over']})',
              style: const TextStyle(color: Colors.black54),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scorecard tab
// ---------------------------------------------------------------------------

class _ScorecardTab extends ConsumerWidget {
  const _ScorecardTab({
    required this.matchId,
    required this.innings,
    required this.allInnings,
    required this.teams,
    required this.names,
    required this.onPickInnings,
  });

  final String matchId;
  final Map<String, dynamic> innings;
  final List<Map<String, dynamic>> allInnings;
  final Map<String, String> teams;
  final Map<String, String> names;
  final ValueChanged<String> onPickInnings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inningsStateProvider(innings['id'] as String));
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => Center(child: Text('Could not load scorecard.\n$e')),
      data: (s) => _content(s),
    );
  }

  Widget _content(Map<String, dynamic> s) {
    final batting = _list(s['batting']);
    final bowling = _list(s['bowling']);
    final fow = _list(s['fall_of_wickets']);
    final extras = s['extras'] as Map<String, dynamic>? ?? const {};
    final dnb = (s['did_not_bat'] as List?)?.cast<String>() ?? const [];
    final strikerId = s['striker_id'] as String?;
    final nonStrikerId = s['non_striker_id'] as String?;
    final battingTeam = teams[innings['batting_team_id']] ?? 'Batting';
    final extrasTotal = _i(extras['wides']) +
        _i(extras['no_balls']) +
        _i(extras['byes']) +
        _i(extras['leg_byes']) +
        _i(extras['penalty']);

    // A batter at the crease who has not yet faced a ball is "batting" (0*),
    // not "did not bat".
    final atCrease = <String>{?strikerId, ?nonStrikerId};
    final battedIds = {for (final b in batting) b['batter_id'] as String};
    final battingRows = [
      ...batting,
      for (final id in atCrease)
        if (!battedIds.contains(id))
          {'batter_id': id, 'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0},
    ];
    final dnbShown = [for (final id in dnb) if (!atCrease.contains(id)) id];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (allInnings.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final inn in allInnings)
                  ChoiceChip(
                    label: Text(
                      '${teams[inn['batting_team_id']] ?? 'Innings'} '
                      '(Inns ${_i(inn['innings_number'])})',
                    ),
                    selected: inn['id'] == innings['id'],
                    onSelected: (_) => onPickInnings(inn['id'] as String),
                  ),
              ],
            ),
          ),
        Text(
          '$battingTeam  -  ${_i(s['runs'])}/${_i(s['wickets'])} (${s['over']})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        // Batting card
        _row(
          const ['Batsman', 'R', 'B', '4s', '6s', 'SR'],
          header: true,
        ),
        const Divider(height: 8),
        for (final b in battingRows)
          _row([
            '${names[b['batter_id']] ?? '-'}'
                '${b['batter_id'] == strikerId || b['batter_id'] == nonStrikerId ? '  *' : ''}',
            '${_i(b['runs'])}',
            '${_i(b['balls'])}',
            '${_i(b['fours'])}',
            '${_i(b['sixes'])}',
            _sr(_i(b['runs']), _i(b['balls'])),
          ]),
        const SizedBox(height: 8),
        Text(
          'Extras  $extrasTotal'
          '  (wd ${_i(extras['wides'])}, nb ${_i(extras['no_balls'])},'
          ' b ${_i(extras['byes'])}, lb ${_i(extras['leg_byes'])})',
          style: const TextStyle(color: Colors.black54),
        ),
        if (dnbShown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Did not bat: ${dnbShown.map((id) => names[id] ?? '-').join(', ')}',
              style: const TextStyle(color: Colors.black54),
            ),
          ),
        if (fow.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Fall of wickets', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            fow
                .map((w) =>
                    '${_i(w['wicket_number'])}-${_i(w['score_at_fall'])}'
                    ' (${names[w['dismissed_player_id']] ?? '-'}, ${w['over']})')
                .join('   '),
            style: const TextStyle(color: Colors.black54),
          ),
        ],
        const SizedBox(height: 20),
        const Text('Bowling', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        _row(const ['Bowler', 'O', 'M', 'R', 'W', 'Econ'], header: true),
        const Divider(height: 8),
        for (final b in bowling)
          _row([
            names[b['bowler_id']] ?? '-',
            '${b['overs'] ?? '0.0'}',
            '${_i(b['maidens'])}',
            '${_i(b['runs_conceded'])}',
            '${_i(b['wickets'])}',
            '${b['economy'] ?? '-'}',
          ]),
      ],
    );
  }

  Widget _row(List<String> cells, {bool header = false}) {
    final style = TextStyle(
      fontWeight: header ? FontWeight.bold : FontWeight.normal,
      color: header ? Colors.black87 : Colors.black,
      fontSize: header ? 13 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text(cells[0], style: style)),
          for (var i = 1; i < cells.length; i++)
            Expanded(
              flex: 2,
              child: Text(cells[i], style: style, textAlign: TextAlign.end),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Charts tab
// ---------------------------------------------------------------------------

class _ChartsTab extends ConsumerWidget {
  const _ChartsTab({required this.matchId, required this.innings});

  final String matchId;
  final Map<String, dynamic> innings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inningsStateProvider(innings['id'] as String));
    final wagon = ref.watch(inningsWagonProvider(innings['id'] as String));
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => Center(child: Text('Could not load charts.\n$e')),
      data: (s) => _content(s, wagon.value ?? const []),
    );
  }

  Widget _content(Map<String, dynamic> s, List<Map<String, dynamic>> wagonRows) {
    final perOver = _list(s['per_over']);
    final worm = _list(s['worm']);
    final shots = [
      for (final r in wagonRows)
        WagonShot(
          x: (r['wagon_x'] as num).toDouble(),
          y: (r['wagon_y'] as num).toDouble(),
          runs: _i(r['runs_off_bat']),
        ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const Text('Runs per over', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          key: const Key('manhattan_chart'),
          height: 200,
          child: perOver.isEmpty
              ? const Center(child: Text('No overs bowled yet.'))
              : BarChart(_manhattan(perOver)),
        ),
        const SizedBox(height: 28),
        const Text('Worm (cumulative runs)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          key: const Key('worm_chart'),
          height: 200,
          child: worm.isEmpty
              ? const Center(child: Text('No overs bowled yet.'))
              : LineChart(_worm(worm)),
        ),
        const SizedBox(height: 28),
        const Text('Shots (wagon wheel)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          key: const Key('wagon_chart'),
          height: 320,
          child: Center(
            child: shots.isEmpty
                ? const Text('No shots recorded yet.')
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: WagonField(shots: shots),
                  ),
          ),
        ),
      ],
    );
  }

  BarChartData _manhattan(List<Map<String, dynamic>> perOver) {
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 28),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, meta) =>
                Text('${v.toInt()}', style: const TextStyle(fontSize: 10)),
          ),
        ),
      ),
      barGroups: [
        for (final o in perOver)
          BarChartGroupData(
            x: _i(o['over_number']),
            barRods: [
              BarChartRodData(
                toY: _i(o['runs_in_over']).toDouble(),
                color: _i(o['wickets_in_over']) > 0
                    ? const Color(0xFFD7263D)
                    : _kTeal,
                width: 10,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ],
          ),
      ],
    );
  }

  LineChartData _worm(List<Map<String, dynamic>> worm) {
    return LineChartData(
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 28),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, meta) =>
                Text('${v.toInt()}', style: const TextStyle(fontSize: 10)),
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (final w in worm)
              FlSpot(_i(w['over']).toDouble(), _i(w['cumulative_runs']).toDouble()),
          ],
          isCurved: false,
          color: _kTeal,
          barWidth: 3,
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Info tab
// ---------------------------------------------------------------------------

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.match, required this.teams});

  final Map<String, dynamic> match;
  final Map<String, String> teams;

  @override
  Widget build(BuildContext context) {
    final a = teams[match['team_a_id']] ?? 'Team A';
    final b = teams[match['team_b_id']] ?? 'Team B';
    final tossWinner = teams[match['toss_winner_id']];
    final decision = match['toss_decision'] as String?;
    final venue = match['venue'] as String?;
    final overs = _i(match['overs_limit']);
    final bpo = _i(match['balls_per_over']);

    Widget tile(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 90,
                child: Text(label, style: const TextStyle(color: Colors.black54)),
              ),
              Expanded(child: Text(value)),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text('$a v $b',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        tile('Format', '$overs overs${bpo > 0 ? ' ($bpo balls/over)' : ''}'),
        if (venue != null && venue.isNotEmpty) tile('Venue', venue),
        tile(
          'Toss',
          tossWinner != null && decision != null
              ? '$tossWinner won and chose to $decision'
              : 'Not decided',
        ),
        tile('Status', (match['status'] as String?) ?? '-'),
      ],
    );
  }
}
