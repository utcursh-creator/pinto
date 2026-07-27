import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../discover/data/discover_repository.dart';
import '../../identity/data/identity_providers.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';
import '../../../core/ui/app_primitives.dart';
import '../../../core/ui/human_error.dart';

class StartMatchScreen extends ConsumerStatefulWidget {
  const StartMatchScreen({
    this.initialOpponentId,
    this.initialOvers,
    this.initialVenue,
    this.initialMatchAt,
    this.proposeToAuthorId,
    super.key,
  });

  /// When arriving from a "Propose a match" bridge on a team_seeking_opponent
  /// post, the opponent team + overs + venue + date carry over and, on
  /// creation, the poster is DM'd the match (MTCH-7).
  final String? initialOpponentId;
  final String? initialOvers;
  final String? initialVenue;
  final String? initialMatchAt; // ISO-8601
  final String? proposeToAuthorId;

  @override
  ConsumerState<StartMatchScreen> createState() => _StartMatchScreenState();
}

class _StartMatchScreenState extends ConsumerState<StartMatchScreen> {
  String? _teamA;
  String? _teamB;
  late final _overs =
      TextEditingController(text: widget.initialOvers?.trim().isNotEmpty ?? false
          ? widget.initialOvers!.trim()
          : '20');
  late final _venue = TextEditingController(text: widget.initialVenue ?? '');
  late DateTime? _matchAt =
      DateTime.tryParse(widget.initialMatchAt ?? '')?.toLocal();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _teamB = widget.initialOpponentId;
  }

  @override
  void dispose() {
    _overs.dispose();
    _venue.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final overs = int.tryParse(_overs.text.trim());
    if (_teamA == null || _teamB == null || overs == null) {
      setState(() => _error = 'Pick both teams and overs.');
      return;
    }
    if (_teamA == _teamB) {
      setState(() => _error = 'Teams must be different.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo0 = ref.read(matchRepositoryProvider);
      final id = await repo0.createMatch(
            teamA: _teamA!,
            teamB: _teamB!,
            overs: overs,
            venue: _venue.text.trim(),
          );
      // MTCH-7: the post's date/time survives onto the match
      if (_matchAt != null) {
        try {
          await repo0.updateMatchSchedule(
              matchId: id,
              scheduledAt: _matchAt,
              venue: _venue.text.trim());
        } catch (_) {/* non-fatal: the match exists either way */}
      }
      // MTCH-7: notify the poster who was seeking an opponent.
      if (widget.proposeToAuthorId != null) {
        try {
          final repo = ref.read(discoverRepositoryProvider);
          final threadId =
              await repo.getOrCreateDmThread(widget.proposeToAuthorId!);
          await repo.sendDm(threadId,
              'I proposed a match against your team ($overs overs). '
              "Let's set it up - watch it live once we start: ${Routes.viewMatch(id)}");
        } catch (_) {/* non-fatal: the match is created regardless */}
      }
      // the Matches list is cached; a new match must appear on return
      ref.invalidate(myMatchesProvider);
      if (mounted) context.pushReplacement(Routes.matchSquads(id));
    } catch (e) {
      setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myTeams = ref.watch(myTeamsProvider);
    final allTeams = ref.watch(allTeamsProvider);
    return AdaptiveScaffold(
      title: 'Start a match',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Your team', style: Theme.of(context).textTheme.labelLarge),
          myTeams.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(humanError(e)),
            data: (rows) {
              // A brand-new signed-in user has no team, so this dropdown was
              // empty, "Next: squads" stayed enabled, and the primary CTA of
              // the whole app could never succeed - with no route to creating a
              // team from here (penetration review 2026-07-07).
              if (rows.isEmpty) {
                return AppEmpty(
                  icon: Icons.groups_outlined,
                  title: 'You need a team first',
                  message:
                      'A match is played between two teams. Create yours - it '
                      'takes a moment, and you can add guest players later.',
                  actionLabel: 'Create a team',
                  onAction: () => context.push(Routes.createTeam),
                );
              }
              return DropdownButton<String>(
                isExpanded: true,
                value: _teamA,
                hint: const Text('Choose your team'),
                items: [
                  for (final r in rows)
                    DropdownMenuItem(
                      value: (r['teams'] as Map)['id'] as String,
                      child: Text((r['teams'] as Map)['name'] as String),
                    ),
                ],
                onChanged: (v) => setState(() => _teamA = v),
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Opponent', style: Theme.of(context).textTheme.labelLarge),
          allTeams.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(humanError(e)),
            data: (rows) => DropdownButton<String>(
              isExpanded: true,
              value: _teamB,
              hint: const Text('Choose the opponent'),
              items: [
                // MTCH-6: don't offer your own team as the opponent.
                for (final t in rows)
                  if (t['id'] != _teamA)
                    DropdownMenuItem(
                      value: t['id'] as String,
                      child: Text(t['name'] as String),
                    ),
              ],
              onChanged: (v) => setState(() => _teamB = v),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _overs,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Overs'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _venue,
            decoration: const InputDecoration(labelText: 'Venue (optional)'),
          ),
          // MTCH-7: the date carried from a discover post (editable)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(_matchAt == null
                ? 'Date & time (optional)'
                : '${_matchAt!.day}/${_matchAt!.month}/${_matchAt!.year} '
                    '${_matchAt!.hour.toString().padLeft(2, '0')}:'
                    '${_matchAt!.minute.toString().padLeft(2, '0')}'),
            trailing: _matchAt == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _matchAt = null),
                  ),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _matchAt ?? now,
                firstDate: now.subtract(const Duration(days: 1)),
                lastDate: now.add(const Duration(days: 365)),
              );
              if (d == null || !context.mounted) return;
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(_matchAt ?? now),
              );
              setState(() => _matchAt = DateTime(
                  d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0));
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: const Text('Next: squads'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
