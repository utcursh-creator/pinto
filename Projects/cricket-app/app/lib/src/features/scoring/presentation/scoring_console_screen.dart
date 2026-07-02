import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';
import 'wagon_field.dart';

/// The live ball-by-ball scorer console. Reads compute_innings_state for the
/// score/strike, records deliveries via record_ball, re-folds after each ball.
class ScoringConsoleScreen extends ConsumerStatefulWidget {
  const ScoringConsoleScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<ScoringConsoleScreen> createState() =>
      _ScoringConsoleScreenState();
}

class _ScoringConsoleScreenState extends ConsumerState<ScoringConsoleScreen> {
  String? _bowlerId; // selected for the current over
  bool _busy = false;

  MatchRepository get _repo => ref.read(matchRepositoryProvider);

  Map<String, String> _names(List<Map<String, dynamic>> squad) => {
        for (final s in squad)
          s['team_member_id'] as String:
              memberName(s['team_members'] as Map<String, dynamic>),
      };

  Future<void> _afterBall(String inningsId, int bpo) async {
    ref.invalidate(inningsStateProvider(inningsId));
    final fresh = await ref.read(inningsStateProvider(inningsId).future);
    final legal = (fresh['legal_balls'] as num?)?.toInt() ?? 0;
    if (legal > 0 && legal % bpo == 0) {
      if (mounted) setState(() => _bowlerId = null);
    }
  }

  Future<void> _record(
    String inningsId,
    int bpo, {
    int runs = 0,
    int wides = 0,
    int noBall = 0,
    int byes = 0,
    int legByes = 0,
    String? noballSecondaryKind,
    String? wicketType,
    String? dismissedId,
    String? incomingId,
    String? fielderId,
    bool? crossed,
  }) async {
    if (_bowlerId == null || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await _repo.recordBall(
        inningsId: inningsId,
        bowlerId: _bowlerId!,
        runsOffBat: runs,
        wides: wides,
        noBallPenalty: noBall,
        byes: byes,
        legByes: legByes,
        noballSecondaryKind: noballSecondaryKind,
        wicketType: wicketType,
        dismissedPlayerId: dismissedId,
        incomingBatterId: incomingId,
        fielderId: fielderId,
        crossed: crossed,
      );
      await _afterBall(inningsId, bpo);
      if (res.wagonApplicable && res.deliveryId != null && mounted) {
        await _promptWagon(res.deliveryId!);
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// After a directional bat shot, ask the scorer where the ball went.
  Future<void> _promptWagon(String deliveryId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Where did the ball go?',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('Skip'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: WagonField(
                  onTap: (x, y, zone) async {
                    try {
                      await _repo.setDeliveryWagon(
                        deliveryId: deliveryId,
                        x: x,
                        y: y,
                        zone: zone,
                      );
                    } catch (_) {/* non-fatal: skip the shot */}
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) m.showSnackBar(SnackBar(content: Text(msg)));
  }

  /// SCOR-7: multi-run / combination extras (wide+N, no-ball+N off the bat, N
  /// byes, N leg-byes) that the quick +1 pad buttons can't express.
  Future<void> _extras(String inningsId, int bpo) async {
    String type = 'wide';
    int runs = 0;
    String labelFor(String t) => switch (t) {
          'wide' => 'Wide',
          'no_ball' => 'No-ball',
          'byes' => 'Byes',
          'leg_byes' => 'Leg-byes',
          _ => t,
        };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final needsRun = type == 'byes' || type == 'leg_byes';
          final hint = switch (type) {
            'wide' => 'Extra runs run off the wide (the wide itself counts 1)',
            'no_ball' => 'Runs off the bat (the no-ball itself counts 1)',
            'byes' => 'Byes run',
            'leg_byes' => 'Leg-byes run',
            _ => '',
          };
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Extra'),
                  Wrap(spacing: 8, children: [
                    for (final t in const ['wide', 'no_ball', 'byes', 'leg_byes'])
                      ChoiceChip(
                        label: Text(labelFor(t)),
                        selected: type == t,
                        onSelected: (_) => setSheet(() => type = t),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text(hint)),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: runs > 0 ? () => setSheet(() => runs--) : null,
                    ),
                    Text('$runs', style: const TextStyle(fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setSheet(() => runs++),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (needsRun && runs < 1)
                        ? null
                        : () => Navigator.pop(context, true),
                    child: const Text('Record'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (ok ?? false) {
      switch (type) {
        case 'wide':
          await _record(inningsId, bpo, wides: 1 + runs);
        case 'no_ball':
          await _record(inningsId, bpo,
              noBall: 1,
              runs: runs,
              noballSecondaryKind: runs > 0 ? 'off_bat' : null);
        case 'byes':
          await _record(inningsId, bpo, byes: runs);
        case 'leg_byes':
          await _record(inningsId, bpo, legByes: runs);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(matchProvider(widget.matchId));
    final innings = ref.watch(currentInningsProvider(widget.matchId));
    final squad = ref.watch(matchSquadProvider(widget.matchId));

    return AdaptiveScaffold(
      title: 'Live scoring',
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_note),
          tooltip: 'Ball log / corrections',
          onPressed: () => context.push(Routes.ballLog(widget.matchId)),
        ),
        IconButton(
          icon: const Icon(Icons.swap_horiz),
          tooltip: 'Hand over scoring',
          onPressed: () =>
              context.push(Routes.transferScorer(widget.matchId)),
        ),
        IconButton(
          icon: const Icon(Icons.visibility_outlined),
          tooltip: 'Watch (public view)',
          onPressed: () => context.push(Routes.viewMatch(widget.matchId)),
        ),
      ],
      body: (match.isLoading || innings.isLoading || squad.isLoading)
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _content(
              match.value,
              innings.value,
              squad.value ?? const [],
              ref.watch(matchTeamNamesProvider(widget.matchId)).value ??
                  const <String, String>{},
            ),
    );
  }

  Widget _content(
    Map<String, dynamic>? match,
    Map<String, dynamic>? innings,
    List<Map<String, dynamic>> squad,
    Map<String, String> teamNames,
  ) {
    if (innings == null) {
      return const Center(child: Text('No innings yet. Finish setup first.'));
    }
    final inningsId = innings['id'] as String;
    final bpo = (match?['balls_per_over'] as num?)?.toInt() ?? 6;
    final bowlingTeam = innings['bowling_team_id'] as String;
    final battingTeam = innings['batting_team_id'] as String;
    final names = _names(squad);
    final state = ref.watch(inningsStateProvider(inningsId));

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => Center(child: Text('Could not load score.\n$e')),
      data: (s) {
        final runs = (s['runs'] as num?)?.toInt() ?? 0;
        final wkts = (s['wickets'] as num?)?.toInt() ?? 0;
        final over = s['over']?.toString() ?? '0.0';
        final strikerId = s['striker_id'] as String?;
        final nonStrikerId = s['non_striker_id'] as String?;
        final target = innings['target'] as int?;
        final ended = s['innings_status'] == 'completed';
        final matchDone = match?['status'] == 'complete' ||
            match?['status'] == 'abandoned';
        // Chase line: "Need R off B  (RRR x.xx)".
        final runsReq = (s['runs_required'] as num?)?.toInt();
        final ballsRem = (s['balls_remaining'] as num?)?.toInt();
        final rrr = s['rrr'];

        return Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFF0F2E26),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$runs/$wkts',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Over $over'
                    '${target != null ? '   -   target $target' : ''}',
                    style: const TextStyle(color: Color(0xFF7DD3B9)),
                  ),
                  if (target != null && !ended && runsReq != null && ballsRem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Need $runsReq off $ballsRem'
                        '${rrr != null ? '   (RRR $rrr)' : ''}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
            if (s['free_hit_active'] == true && !ended)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF3CD),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
                child: const Text('FREE HIT',
                    style: TextStyle(
                        color: Color(0xFF8A6D00), fontWeight: FontWeight.bold)),
              ),
            if (ended)
              Expanded(
                child: _endPanel(
                  s: s,
                  innings: innings,
                  squad: squad,
                  teamNames: teamNames,
                  battingTeam: battingTeam,
                  bowlingTeam: bowlingTeam,
                  target: target,
                  matchDone: matchDone,
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('On strike: ${names[strikerId] ?? '-'}  *'),
                    ),
                    Expanded(child: Text(names[nonStrikerId] ?? '-')),
                  ],
                ),
              ),
              ListTile(
                dense: true,
                title: Text(
                  _bowlerId == null
                      ? 'Select a bowler to start the over'
                      : 'Bowling: ${names[_bowlerId] ?? '-'}',
                ),
                trailing: TextButton(
                  onPressed: () => _pickBowler(squad, bowlingTeam, names),
                  child: Text(_bowlerId == null ? 'Pick' : 'Change'),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: AbsorbPointer(
                  absorbing: _bowlerId == null || _busy,
                  child: Opacity(
                    opacity: _bowlerId == null ? 0.4 : 1,
                    child: _pad(
                        inningsId, bpo, squad, battingTeam, bowlingTeam, names, s),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Shown when the current innings has ended. Three cases:
  ///  * match already resolved -> just offer the scorecard;
  ///  * 1st innings done (no target) -> innings break, start the chase;
  ///  * 2nd innings done (target set) -> the fold's computed result + finish.
  Widget _endPanel({
    required Map<String, dynamic> s,
    required Map<String, dynamic> innings,
    required List<Map<String, dynamic>> squad,
    required Map<String, String> teamNames,
    required String battingTeam,
    required String bowlingTeam,
    required int? target,
    required bool matchDone,
  }) {
    final runs = (s['runs'] as num?)?.toInt() ?? 0;
    final wkts = (s['wickets'] as num?)?.toInt() ?? 0;
    final battingName = teamNames[battingTeam] ?? 'Batting side';

    Widget wrap(List<Widget> children) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );

    if (matchDone) {
      return wrap([
        const Text('Match complete',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_resultLine(s['result'], teamNames)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.push(Routes.viewMatch(widget.matchId)),
          child: const Text('View scorecard'),
        ),
      ]);
    }

    if (target == null) {
      // 1st innings done -> break, then start the chase.
      final chaseTarget = runs + 1;
      return wrap([
        const Text('Innings break',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('$battingName finished on $runs/$wkts.'),
        const SizedBox(height: 4),
        Text('Target: $chaseTarget   (they must chase $chaseTarget to win)',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _startSecondInnings(
                    chaseBatting: bowlingTeam, // sides swap for the 2nd innings
                    chaseBowling: battingTeam,
                    squad: squad,
                    teamNames: teamNames,
                    target: chaseTarget,
                  ),
          child: const Text('Start 2nd innings'),
        ),
      ]);
    }

    // 2nd innings done -> finish with the fold's computed result.
    return wrap([
      const Text('Match over',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(_resultLine(s['result'], teamNames),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _busy ? null : () => _finishMatch(s['result'], teamNames),
        child: const Text('Finish match & view scorecard'),
      ),
    ]);
  }

  /// Human result from the fold's `result` jsonb (win_by_wickets/runs/tie).
  String _resultLine(dynamic result, Map<String, String> teamNames) {
    if (result is! Map) return 'Result pending.';
    final type = result['result_type'] as String?;
    final winner = teamNames[result['winner_team_id']] ?? 'The winning side';
    switch (type) {
      case 'win_by_wickets':
        final w = (result['margin_wickets'] as num?)?.toInt();
        final b = (result['balls_remaining'] as num?)?.toInt();
        return '$winner won by $w wicket${w == 1 ? '' : 's'}'
            '${b != null ? ' ($b ball${b == 1 ? '' : 's'} left)' : ''}.';
      case 'win_by_runs':
        final r = (result['margin_runs'] as num?)?.toInt();
        return '$winner won by $r run${r == 1 ? '' : 's'}.';
      case 'tie':
        return 'Match tied.';
      default:
        return 'Match complete.';
    }
  }

  Future<void> _finishMatch(dynamic result, Map<String, String> teamNames) async {
    if (result is! Map) return;
    setState(() => _busy = true);
    try {
      final type = result['result_type'] as String? ?? 'no_result';
      await _repo.setResult(
        matchId: widget.matchId,
        resultType: type,
        winnerTeamId: result['winner_team_id'] as String?,
        note: _resultLine(result, teamNames), // the full human result sentence
      );
      ref.invalidate(matchProvider(widget.matchId));
      if (mounted) context.pushReplacement(Routes.viewMatch(widget.matchId));
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSecondInnings({
    required String chaseBatting,
    required String chaseBowling,
    required List<Map<String, dynamic>> squad,
    required Map<String, String> teamNames,
    required int target,
  }) async {
    final openers = await _pickTwoOpeners(chaseBatting, squad, teamNames);
    if (openers == null) return;
    setState(() => _busy = true);
    try {
      await _repo.startInnings(
        matchId: widget.matchId,
        inningsNumber: 2,
        battingTeam: chaseBatting,
        bowlingTeam: chaseBowling,
        openingStriker: openers.$1,
        openingNonStriker: openers.$2,
        target: target,
      );
      ref.invalidate(currentInningsProvider(widget.matchId));
      ref.invalidate(matchInningsListProvider(widget.matchId));
      if (mounted) setState(() => _bowlerId = null);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bottom sheet: pick striker + non-striker for the chasing side.
  Future<(String, String)?> _pickTwoOpeners(
    String battingTeam,
    List<Map<String, dynamic>> squad,
    Map<String, String> teamNames,
  ) {
    final batters = [
      for (final m in squad)
        if (m['team_id'] == battingTeam) m,
    ];
    String? striker;
    String? nonStriker;
    return showModalBottomSheet<(String, String)?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Widget picker(String label, String? value, ValueChanged<String?> on) =>
              Row(children: [
                SizedBox(width: 110, child: Text(label)),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: value,
                    hint: const Text('Choose'),
                    items: [
                      for (final b in batters)
                        DropdownMenuItem(
                          value: b['team_member_id'] as String,
                          child: Text(
                              memberName(b['team_members'] as Map<String, dynamic>)),
                        ),
                    ],
                    onChanged: on,
                  ),
                ),
              ]);
          final ready =
              striker != null && nonStriker != null && striker != nonStriker;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${teamNames[battingTeam] ?? 'Chasing side'} - opening pair',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  picker('Striker', striker, (v) => setSheet(() => striker = v)),
                  picker('Non-striker', nonStriker,
                      (v) => setSheet(() => nonStriker = v)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: ready
                        ? () => Navigator.pop(context, (striker!, nonStriker!))
                        : null,
                    child: const Text('Start chase'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pad(
    String inningsId,
    int bpo,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    String bowlingTeam,
    Map<String, String> names,
    Map<String, dynamic> s,
  ) {
    Widget runBtn(int n, {bool boundary = false}) => _Btn(
          label: '$n',
          color: boundary ? const Color(0xFFE1F5EE) : null,
          onTap: () => _record(inningsId, bpo, runs: n),
        );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [runBtn(0), runBtn(1), runBtn(2)]),
          Row(children: [runBtn(3), runBtn(4, boundary: true), runBtn(6, boundary: true)]),
          Row(
            children: [
              _Btn(label: 'Wd', onTap: () => _record(inningsId, bpo, wides: 1)),
              _Btn(label: 'Nb', onTap: () => _record(inningsId, bpo, noBall: 1)),
              _Btn(label: 'B', onTap: () => _record(inningsId, bpo, byes: 1)),
              _Btn(label: 'Lb', onTap: () => _record(inningsId, bpo, legByes: 1)),
            ],
          ),
          Row(
            children: [
              _Btn(label: 'Extras', onTap: () => _extras(inningsId, bpo)),
              _Btn(
                label: 'WICKET',
                color: const Color(0xFFFFE5E2),
                onTap: () => _wicket(
                    inningsId, bpo, squad, battingTeam, bowlingTeam, names, s),
              ),
              _Btn(
                label: 'Undo',
                onTap: () async {
                  await _repo.undoLastBall(inningsId);
                  ref.invalidate(inningsStateProvider(inningsId));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickBowler(
    List<Map<String, dynamic>> squad,
    String bowlingTeam,
    Map<String, String> names,
  ) async {
    final bowlers = [
      for (final s in squad)
        if (s['team_id'] == bowlingTeam) s['team_member_id'] as String,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Select bowler')),
            for (final id in bowlers)
              ListTile(title: Text(names[id] ?? '-'), onTap: () => Navigator.pop(context, id)),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _bowlerId = picked);
  }

  static const _allWicketTypes = [
    'bowled', 'caught', 'lbw', 'run_out', 'stumped', 'hit_wicket',
    'retired_out', 'obstructing', 'timed_out', 'hit_ball_twice',
  ];
  // Only these are legal on a free hit (mirrors record_ball's guard).
  static const _freeHitWicketTypes = ['run_out', 'obstructing', 'hit_ball_twice'];

  static bool _needsWhoOut(String t) =>
      t == 'run_out' || t == 'obstructing' || t == 'retired_out';
  static bool _needsFielder(String t) =>
      t == 'caught' || t == 'stumped' || t == 'run_out';
  static bool _needsCrossedRuns(String t) => t == 'run_out' || t == 'obstructing';

  String _wicketLabel(String t) => switch (t) {
        'bowled' => 'Bowled',
        'caught' => 'Caught',
        'lbw' => 'LBW',
        'run_out' => 'Run out',
        'stumped' => 'Stumped',
        'hit_wicket' => 'Hit wicket',
        'retired_out' => 'Retired out',
        'obstructing' => 'Obstructing',
        'timed_out' => 'Timed out',
        'hit_ball_twice' => 'Hit the ball twice',
        _ => t,
      };

  Future<void> _wicket(
    String inningsId,
    int bpo,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    String bowlingTeam,
    Map<String, String> names,
    Map<String, dynamic> s,
  ) async {
    final strikerId = s['striker_id'] as String?;
    final nonStrikerId = s['non_striker_id'] as String?;
    final freeHit = s['free_hit_active'] == true;
    final wktsRem = (s['wickets_remaining'] as num?)?.toInt() ?? 99;
    final isLastWicket = wktsRem <= 1;

    // batters already dismissed (from the fold's fall of wickets)
    final gone = <String>{
      for (final w in (s['fall_of_wickets'] as List? ?? const []))
        if ((w as Map)['dismissed_player_id'] != null)
          w['dismissed_player_id'] as String,
    };
    final availableIncoming = [
      for (final m in squad)
        if (m['team_id'] == battingTeam)
          m['team_member_id'] as String,
    ].where((id) =>
        id != strikerId && id != nonStrikerId && !gone.contains(id)).toList();
    final fielders = [
      for (final m in squad)
        if (m['team_id'] == bowlingTeam) m['team_member_id'] as String,
    ];

    final types = freeHit ? _freeHitWicketTypes : _allWicketTypes;
    String type = types.first;
    String whoOut = 'striker';
    String? fielder;
    bool crossed = false;
    int runs = 0;
    String? incoming;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final needIncoming = !isLastWicket;
          final canRecord = !needIncoming || incoming != null;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (freeHit)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Free hit - only a run-out counts',
                            style: TextStyle(color: Color(0xFFB26A00))),
                      ),
                    const Text('How out?'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final t in types)
                          ChoiceChip(
                            label: Text(_wicketLabel(t)),
                            selected: type == t,
                            onSelected: (_) => setSheet(() => type = t),
                          ),
                      ],
                    ),
                    if (_needsWhoOut(type)) ...[
                      const SizedBox(height: 12),
                      const Text('Who is out?'),
                      Wrap(spacing: 8, children: [
                        ChoiceChip(
                          label: Text(names[strikerId] ?? 'Striker'),
                          selected: whoOut == 'striker',
                          onSelected: (_) => setSheet(() => whoOut = 'striker'),
                        ),
                        ChoiceChip(
                          label: Text(names[nonStrikerId] ?? 'Non-striker'),
                          selected: whoOut == 'non_striker',
                          onSelected: (_) =>
                              setSheet(() => whoOut = 'non_striker'),
                        ),
                      ]),
                    ],
                    if (_needsCrossedRuns(type)) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Text('Runs completed'),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed:
                              runs > 0 ? () => setSheet(() => runs--) : null,
                        ),
                        Text('$runs', style: const TextStyle(fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setSheet(() => runs++),
                        ),
                      ]),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Batters had crossed'),
                        value: crossed,
                        onChanged: (v) => setSheet(() => crossed = v),
                      ),
                    ],
                    if (_needsFielder(type)) ...[
                      const SizedBox(height: 12),
                      const Text('Fielder'),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: fielder,
                        hint: const Text('Choose (optional)'),
                        items: [
                          for (final id in fielders)
                            DropdownMenuItem(
                                value: id, child: Text(names[id] ?? '-')),
                        ],
                        onChanged: (v) => setSheet(() => fielder = v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(isLastWicket
                        ? 'Incoming batter (last wicket - none needed)'
                        : 'Incoming batter'),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: incoming,
                      hint: const Text('Choose'),
                      items: [
                        for (final id in availableIncoming)
                          DropdownMenuItem(
                              value: id, child: Text(names[id] ?? '-')),
                      ],
                      onChanged: (v) => setSheet(() => incoming = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: canRecord
                          ? () => Navigator.pop(context, true)
                          : null,
                      child: const Text('Record wicket'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (ok ?? false) {
      final dismissedId = _needsWhoOut(type) && whoOut == 'non_striker'
          ? nonStrikerId
          : strikerId;
      await _record(
        inningsId,
        bpo,
        runs: _needsCrossedRuns(type) ? runs : 0,
        wicketType: type,
        dismissedId: dismissedId,
        incomingId: incoming,
        fielderId: _needsFielder(type) ? fielder : null,
        crossed: _needsCrossedRuns(type) ? crossed : null,
      );
    }
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.label, required this.onTap, this.color});

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      ),
    );
  }
}
