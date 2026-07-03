import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../discover/data/discover_repository.dart';
import '../../identity/data/identity_providers.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';

class StartMatchScreen extends ConsumerStatefulWidget {
  const StartMatchScreen({
    this.initialOpponentId,
    this.initialOvers,
    this.proposeToAuthorId,
    super.key,
  });

  /// When arriving from a "Propose a match" bridge on a team_seeking_opponent
  /// post, the opponent team + overs are pre-selected and, on creation, the
  /// poster is DM'd the match (MTCH-7).
  final String? initialOpponentId;
  final String? initialOvers;
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
  final _venue = TextEditingController();
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
      final id = await ref.read(matchRepositoryProvider).createMatch(
            teamA: _teamA!,
            teamB: _teamB!,
            overs: overs,
            venue: _venue.text.trim(),
          );
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
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
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
            error: (e, _) => Text('$e'),
            data: (rows) => DropdownButton<String>(
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
            ),
          ),
          const SizedBox(height: 16),
          Text('Opponent', style: Theme.of(context).textTheme.labelLarge),
          allTeams.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
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
          const SizedBox(height: 24),
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
