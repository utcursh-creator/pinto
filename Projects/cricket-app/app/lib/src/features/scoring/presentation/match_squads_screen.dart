import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';

class MatchSquadsScreen extends ConsumerStatefulWidget {
  const MatchSquadsScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<MatchSquadsScreen> createState() => _MatchSquadsScreenState();
}

class _MatchSquadsScreenState extends ConsumerState<MatchSquadsScreen> {
  final Set<String> _selected = {}; // team_member ids
  final Map<String, String> _teamOf = {}; // member id -> team id
  bool _busy = false;
  String? _error;

  Future<void> _next(String teamA, String teamB) async {
    // SCOR-14/M3: validate PER TEAM, not just the combined count - otherwise a
    // side can reach the console with nobody to bat or bowl.
    final a = _selected.where((id) => _teamOf[id] == teamA).length;
    final b = _selected.where((id) => _teamOf[id] == teamB).length;
    if (a < 2 || b < 2) {
      setState(() => _error = 'Pick at least two players for each team.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(matchRepositoryProvider);
      for (final memberId in _selected) {
        await repo.addSquadMember(
          matchId: widget.matchId,
          teamId: _teamOf[memberId]!,
          teamMemberId: memberId,
        );
      }
      if (mounted) context.pushReplacement(Routes.matchToss(widget.matchId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(matchProvider(widget.matchId));
    return AdaptiveScaffold(
      title: 'Squads',
      body: match.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('$e')),
        data: (m) {
          if (m == null) return const Center(child: Text('Match not found.'));
          final teamA = m['team_a_id'] as String;
          final teamB = m['team_b_id'] as String;
          // M1: show real team names, never "Team A"/"Team B".
          final names = ref.watch(matchTeamNamesProvider(widget.matchId)).value ??
              const <String, String>{};
          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    _TeamPicker(
                      matchId: widget.matchId,
                      teamId: teamA,
                      label: names[teamA] ?? 'Team A',
                      selected: _selected,
                      teamOf: _teamOf,
                      onChanged: () => setState(() {}),
                    ),
                    _TeamPicker(
                      matchId: widget.matchId,
                      teamId: teamB,
                      label: names[teamB] ?? 'Team B',
                      selected: _selected,
                      teamOf: _teamOf,
                      onChanged: () => setState(() {}),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      FilledButton(
                        onPressed: _busy ? null : () => _next(teamA, teamB),
                        child: Text('Next: toss (${_selected.length} picked)'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TeamPicker extends ConsumerWidget {
  const _TeamPicker({
    required this.matchId,
    required this.teamId,
    required this.label,
    required this.selected,
    required this.teamOf,
    required this.onChanged,
  });

  final String matchId;
  final String teamId;
  final String label;
  final Set<String> selected;
  final Map<String, String> teamOf;
  final VoidCallback onChanged;

  // SCOR-11: add a guest to THIS side during setup (works for the opponent too).
  Future<void> _addGuest(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add guest player'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(matchRepositoryProvider).addMatchGuest(
            matchId: matchId,
            teamId: teamId,
            guestName: name,
          );
      ref.invalidate(teamMembersProvider(teamId));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not add guest: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(teamMembersProvider(teamId));
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(label),
      children: members.when(
        loading: () => const [LinearProgressIndicator()],
        error: (e, _) => [ListTile(title: Text('$e'))],
        data: (rows) => [
          for (final m in rows)
            CheckboxListTile(
              dense: true,
              title: Text(memberName(m)),
              value: selected.contains(m['id']),
              onChanged: (v) {
                final id = m['id'] as String;
                if (v ?? false) {
                  selected.add(id);
                  teamOf[id] = teamId;
                } else {
                  selected.remove(id);
                  teamOf.remove(id);
                }
                onChanged();
              },
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.person_add_alt_1_outlined, size: 20),
            title: const Text('Add guest player'),
            onTap: () => _addGuest(context, ref),
          ),
        ],
      ),
    );
  }
}
