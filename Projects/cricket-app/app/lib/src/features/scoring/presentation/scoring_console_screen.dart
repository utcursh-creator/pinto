import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';

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
    String? wicketType,
    String? dismissedId,
    String? incomingId,
  }) async {
    if (_bowlerId == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _repo.recordBall(
        inningsId: inningsId,
        bowlerId: _bowlerId!,
        runsOffBat: runs,
        wides: wides,
        noBallPenalty: noBall,
        byes: byes,
        legByes: legByes,
        wicketType: wicketType,
        dismissedPlayerId: dismissedId,
        incomingBatterId: incomingId,
      );
      await _afterBall(inningsId, bpo);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) m.showSnackBar(SnackBar(content: Text(msg)));
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
            ),
    );
  }

  Widget _content(
    Map<String, dynamic>? match,
    Map<String, dynamic>? innings,
    List<Map<String, dynamic>> squad,
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
                ],
              ),
            ),
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
                  child: _pad(inningsId, bpo, squad, battingTeam, names, strikerId),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pad(
    String inningsId,
    int bpo,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    Map<String, String> names,
    String? strikerId,
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
              _Btn(
                label: 'WICKET',
                color: const Color(0xFFFFE5E2),
                onTap: () => _wicket(inningsId, bpo, squad, battingTeam, names, strikerId),
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

  Future<void> _wicket(
    String inningsId,
    int bpo,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    Map<String, String> names,
    String? strikerId,
  ) async {
    final batters = [
      for (final s in squad)
        if (s['team_id'] == battingTeam) s['team_member_id'] as String,
    ];
    String type = 'bowled';
    String? incoming;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
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
                const Text('How out?'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in const [
                      'bowled',
                      'caught',
                      'lbw',
                      'run_out',
                      'stumped',
                    ])
                      ChoiceChip(
                        label: Text(t),
                        selected: type == t,
                        onSelected: (_) => setSheet(() => type = t),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Incoming batter'),
                DropdownButton<String>(
                  isExpanded: true,
                  value: incoming,
                  hint: const Text('Choose'),
                  items: [
                    for (final id in batters)
                      DropdownMenuItem(value: id, child: Text(names[id] ?? '-')),
                  ],
                  onChanged: (v) => setSheet(() => incoming = v),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Record wicket'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok ?? false) {
      await _record(
        inningsId,
        bpo,
        wicketType: type,
        dismissedId: strikerId,
        incomingId: incoming,
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
