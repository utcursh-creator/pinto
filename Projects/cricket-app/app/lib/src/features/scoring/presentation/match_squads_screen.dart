import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';
import '../../../core/ui/human_error.dart';
import '../../../core/platform/error_retry.dart';

class MatchSquadsScreen extends ConsumerStatefulWidget {
  const MatchSquadsScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<MatchSquadsScreen> createState() => _MatchSquadsScreenState();
}

class _MatchSquadsScreenState extends ConsumerState<MatchSquadsScreen> {
  // SCOR-13: a Dart Set is insertion-ordered - the order players are picked
  // IS the batting order, shown as a number on each selected row.
  final Set<String> _selected = {}; // team_member ids, in batting order
  final Map<String, String> _teamOf = {}; // member id -> team id
  final Map<String, String?> _captainOf = {}; // team id -> member id
  final Map<String, String?> _keeperOf = {}; // team id -> member id
  bool _busy = false;
  bool _prefilled = false;
  String? _error;

  /// Resuming a match whose squad was already partly saved used to re-insert the
  /// same rows and die on a raw duplicate-key error, leaving the match stuck in
  /// 'setup' with no way forward (penetration review 2026-07-07).
  /// add_squad_member is now idempotent, and the screen also loads what is
  /// already there so the scorer sees their existing XI instead of a blank slate.
  /// [selectable] is every member still ON the two rosters. A player who has
  /// left the team keeps their match_squad rows (that is the whole point of the
  /// left_at tombstone - old scorecards must still name them), but
  /// teamMembersProvider now filters them out, so prefilling them here put an
  /// id into _selected with no tile to un-tick: invisible, unremovable, and
  /// re-written to the server on "Next: toss" (re-review 2026-07-07).
  /// [started] is true once the match is past setup. BEFORE the first ball the
  /// squad is a PLAN, so a departure should prune it (above). AFTER it, the
  /// squad is a RECORD: set_match_squad is authoritative and REFUSES to drop
  /// anyone who has played ("that player has already played in this match"), so
  /// pruning made the next save fail outright with no tile to tick him back on.
  void _prefillFrom(List<Map<String, dynamic>> squad, Set<String> selectable,
      {required bool started}) {
    if (_prefilled || squad.isEmpty) return;
    _prefilled = true;
    final ordered = [...squad]..sort((x, y) {
        final a = (x['batting_order'] as num?)?.toInt() ?? 1 << 30;
        final b = (y['batting_order'] as num?)?.toInt() ?? 1 << 30;
        return a.compareTo(b);
      });
    for (final row in ordered) {
      final memberId = row['team_member_id'] as String?;
      final teamId = row['team_id'] as String?;
      if (memberId == null || teamId == null) continue;
      if (!started && !selectable.contains(memberId)) continue; // left the team
      _selected.add(memberId);
      _teamOf[memberId] = teamId;
      if (row['is_captain'] == true) _captainOf[teamId] = memberId;
      if (row['is_wicket_keeper'] == true) _keeperOf[teamId] = memberId;
    }
  }

  /// The larger side's size when either exceeds a normal XI, else null.
  int? _oversizedSide(String teamA, String teamB) {
    final a = _selected.where((id) => _teamOf[id] == teamA).length;
    final b = _selected.where((id) => _teamOf[id] == teamB).length;
    final biggest = a > b ? a : b;
    return biggest > 11 ? biggest : null;
  }

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
      // ONE call stating the whole squad, because the two things this screen
      // could not do were REMOVE anybody and fail cleanly (review #2 findings
      // 10 and 25). Writing member-by-member meant un-ticking a saved player
      // changed nothing on the server - he kept turning up in the opening pair,
      // the fielder picker and the public scorecard - and a failure part-way
      // through the loop left rows committed under "Could not save the squads".
      await ref.read(matchRepositoryProvider).setMatchSquad(
            matchId: widget.matchId,
            members: [
              for (final memberId in _selected)
                {
                  'team_id': _teamOf[memberId]!,
                  'team_member_id': memberId,
                  'is_captain': _captainOf[_teamOf[memberId]!] == memberId,
                  'is_keeper': _keeperOf[_teamOf[memberId]!] == memberId,
                },
            ],
          );
      // The squad we just wrote is what the toss screen reads to offer the
      // opening pair. This screen has been watching matchSquadProvider since it
      // opened, so the provider is alive and still holding the value it had
      // BEFORE these writes - an empty list. pushReplacement builds the toss
      // screen in the same frame, so it inherits that stale empty list, and the
      // scorer lands on Striker/Non-striker dropdowns with nothing in them and
      // no way to start the match. Refresh before leaving.
      ref.invalidate(matchSquadProvider(widget.matchId));
      if (mounted) context.pushReplacement(Routes.matchToss(widget.matchId));
    } catch (e) {
      // golden-path audit: an aborted squad save must not fail silently
      if (mounted) setState(() => _error = humanError(e, fallback: 'Could not save the squads.'));
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
        error: (e, _) => ErrorRetry(
          message: humanError(e, fallback: 'Could not load this match.'),
          onRetry: () => ref.invalidate(matchProvider(widget.matchId)),
        ),
        data: (m) {
          if (m == null) return const Center(child: Text('Match not found.'));
          final teamA = m['team_a_id'] as String;
          final teamB = m['team_b_id'] as String;
          // resuming setup: start from the squad already saved, not a blank
          // slate - but only from the players who are still on the rosters, so
          // a departed member cannot be silently carried back into the XI.
          final existing = ref.watch(matchSquadProvider(widget.matchId)).value;
          final rosterA = ref.watch(teamMembersProvider(teamA)).value;
          final rosterB = ref.watch(teamMembersProvider(teamB)).value;
          if (existing != null && rosterA != null && rosterB != null) {
            _prefillFrom(
              existing,
              {for (final r in [...rosterA, ...rosterB]) r['id'] as String},
              started: (m['status'] as String?) != null &&
                  m['status'] != 'setup',
            );
          }
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
                      captainOf: _captainOf,
                      keeperOf: _keeperOf,
                      onChanged: () => setState(() {}),
                    ),
                    _TeamPicker(
                      matchId: widget.matchId,
                      teamId: teamB,
                      label: names[teamB] ?? 'Team B',
                      selected: _selected,
                      teamOf: _teamOf,
                      captainOf: _captainOf,
                      keeperOf: _keeperOf,
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
                      // A squad bigger than eleven silently changes the FORMAT
                      // of the match. all_out is squad_size - 1, so a 13-man
                      // squad does not close at ten wickets: a 12th and 13th
                      // batter come in, and "won by N wickets" is computed off
                      // 12 instead of 10. Rosters are routinely bigger than the
                      // XI, so ticking everyone available is a natural mistake
                      // and nothing said a word about it (review #2, finding
                      // 53).
                      //
                      // NOT a hard cap: 12- and 13-a-side social games are real
                      // and the backend supports them deliberately (squad_size
                      // lives in matches.rules). The point is that choosing one
                      // should be a decision, not an accident.
                      if (_oversizedSide(teamA, teamB) != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'That is ${_oversizedSide(teamA, teamB)} players a '
                            'side, so this match will play as such - all out '
                            'at ${_oversizedSide(teamA, teamB)! - 1} wickets, '
                            'not 10.',
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
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
    required this.captainOf,
    required this.keeperOf,
    required this.onChanged,
  });

  final String matchId;
  final String teamId;
  final String label;
  final Set<String> selected;
  final Map<String, String> teamOf;
  final Map<String, String?> captainOf;
  final Map<String, String?> keeperOf;
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
      messenger?.showSnackBar(SnackBar(content: Text(humanError(e, fallback: 'Could not add guest.'))));
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
        error: (e, _) => [ListTile(title: Text(humanError(e)))],
        data: (rows) {
          // SCOR-13: batting slot = pick order within this team
          final teamOrder = [
            for (final id in selected)
              if (teamOf[id] == teamId) id,
          ];
          String? nameOf(String? id) {
            for (final m in rows) {
              if (m['id'] == id) return memberName(m);
            }
            return null;
          }

          Widget roleRow(String role, Map<String, String?> holder) =>
              ListTile(
                dense: true,
                title: Text(role),
                trailing: DropdownButton<String>(
                  value: holder[teamId],
                  hint: const Text('Pick'),
                  items: [
                    for (final id in teamOrder)
                      DropdownMenuItem(
                          value: id, child: Text(nameOf(id) ?? '-')),
                  ],
                  onChanged: (v) {
                    holder[teamId] = v;
                    onChanged();
                  },
                ),
              );

          return [
            for (final m in rows)
              CheckboxListTile(
                dense: true,
                title: Text(
                  selected.contains(m['id'])
                      ? '${teamOrder.indexOf(m['id'] as String) + 1}.  '
                          '${memberName(m)}'
                      : memberName(m),
                ),
                subtitle: selected.contains(m['id']) &&
                        (captainOf[teamId] == m['id'] ||
                            keeperOf[teamId] == m['id'])
                    ? Text([
                        if (captainOf[teamId] == m['id']) 'captain',
                        if (keeperOf[teamId] == m['id']) 'keeper',
                      ].join(' - '))
                    : null,
                value: selected.contains(m['id']),
                onChanged: (v) {
                  final id = m['id'] as String;
                  if (v ?? false) {
                    selected.add(id);
                    teamOf[id] = teamId;
                  } else {
                    selected.remove(id);
                    teamOf.remove(id);
                    if (captainOf[teamId] == id) captainOf[teamId] = null;
                    if (keeperOf[teamId] == id) keeperOf[teamId] = null;
                  }
                  onChanged();
                },
              ),
            // SCOR-13: tag the captain + wicket-keeper (order of the checks
            // above is the batting order)
            if (teamOrder.length >= 2) ...[
              roleRow('Captain', captainOf),
              roleRow('Wicket-keeper', keeperOf),
            ],
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_add_alt_1_outlined, size: 20),
              title: const Text('Add guest player'),
              onTap: () => _addGuest(context, ref),
            ),
          ];
        },
      ),
    );
  }
}
