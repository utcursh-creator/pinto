import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';
import '../../../core/ui/human_error.dart';

class TossOpenersScreen extends ConsumerStatefulWidget {
  const TossOpenersScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<TossOpenersScreen> createState() => _TossOpenersScreenState();
}

class _TossOpenersScreenState extends ConsumerState<TossOpenersScreen> {
  String? _tossWinner; // team id
  String _decision = 'bat';
  String? _striker;
  String? _nonStriker;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(matchProvider(widget.matchId));
    final squad = ref.watch(matchSquadProvider(widget.matchId));

    return AdaptiveScaffold(
      title: 'Toss & openers',
      body: match.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text(humanError(e))),
        data: (m) {
          if (m == null) return const Center(child: Text('Match not found.'));
          final teamA = m['team_a_id'] as String;
          final teamB = m['team_b_id'] as String;
          // M1: real team names, never "Team A"/"Team B".
          final names = ref.watch(matchTeamNamesProvider(widget.matchId)).value ??
              const <String, String>{};
          final battingTeam = _tossWinner == null
              ? null
              : (_decision == 'bat'
                  ? _tossWinner
                  : (_tossWinner == teamA ? teamB : teamA));

          return squad.when(
            loading: () =>
                const Center(child: CircularProgressIndicator.adaptive()),
            error: (e, _) => Center(child: Text(humanError(e))),
            data: (rows) {
              final batters = [
                for (final r in rows)
                  if (r['team_id'] == battingTeam) r,
              ];
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Toss winner', style: Theme.of(context).textTheme.labelLarge),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(names[teamA] ?? 'Team A'),
                        selected: _tossWinner == teamA,
                        onSelected: (_) => setState(() {
                          _tossWinner = teamA;
                          _striker = _nonStriker = null;
                        }),
                      ),
                      ChoiceChip(
                        label: Text(names[teamB] ?? 'Team B'),
                        selected: _tossWinner == teamB,
                        onSelected: (_) => setState(() {
                          _tossWinner = teamB;
                          _striker = _nonStriker = null;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Elected to', style: Theme.of(context).textTheme.labelLarge),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final d in const ['bat', 'bowl'])
                        ChoiceChip(
                          label: Text(d == 'bat' ? 'Bat' : 'Bowl'),
                          selected: _decision == d,
                          onSelected: (_) => setState(() {
                            _decision = d;
                            _striker = _nonStriker = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (battingTeam != null) ...[
                    Text('Opening pair',
                        style: Theme.of(context).textTheme.labelLarge),
                    // SCOR-14: mutually exclusive pickers - the chosen striker
                    // disappears from the non-striker list and vice versa.
                    _picker('Striker', _striker, batters, _nonStriker,
                        (v) => setState(() => _striker = v)),
                    _picker('Non-striker', _nonStriker, batters, _striker,
                        (v) => setState(() => _nonStriker = v)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _start(teamA, teamB, battingTeam, rows),
                    child: const Text('Start match'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _picker(
    String label,
    String? value,
    List<Map<String, dynamic>> batters,
    String? exclude,
    ValueChanged<String?> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            hint: const Text('Choose'),
            items: [
              for (final b in batters)
                if (b['team_member_id'] != exclude)
                  DropdownMenuItem(
                    value: b['team_member_id'] as String,
                    child:
                        Text(memberName(b['team_members'] as Map<String, dynamic>)),
                  ),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Future<void> _start(String teamA, String teamB, String? battingTeam,
      List<Map<String, dynamic>> squadRows) async {
    if (battingTeam == null ||
        _striker == null ||
        _nonStriker == null ||
        _striker == _nonStriker) {
      setState(() => _error = 'Pick the toss, decision and two different openers.');
      return;
    }
    final bowlingTeam = battingTeam == teamA ? teamB : teamA;
    // SCOR-14: an empty bowling side cannot field a ball - catch it here
    // (the server validates too, this is the friendlier stop).
    final bowlers =
        squadRows.where((r) => r['team_id'] == bowlingTeam).length;
    if (bowlers < 2) {
      setState(() => _error =
          'The bowling side needs at least 2 squad members - go back and add them.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(matchRepositoryProvider);
      await repo.setToss(
        matchId: widget.matchId,
        winnerTeamId: _tossWinner!,
        decision: _decision,
      );
      await repo.startInnings(
        matchId: widget.matchId,
        inningsNumber: 1,
        battingTeam: battingTeam,
        bowlingTeam: bowlingTeam,
        openingStriker: _striker!,
        openingNonStriker: _nonStriker!,
      );
      if (mounted) context.pushReplacement(Routes.scoreMatch(widget.matchId));
    } catch (e) {
      // golden-path audit: a silent failure here strands the user at the toss
      if (mounted) setState(() => _error = humanError(e, fallback: 'Could not start the match.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
