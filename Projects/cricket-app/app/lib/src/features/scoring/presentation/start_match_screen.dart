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
  /// Cached so the field can name a team the user just picked without a second
  /// round trip. Null when the opponent arrived as an id from the discover
  /// bridge - the field resolves that one itself.
  String? _teamBName;
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
    // Name what is actually missing. The old line ("Pick both teams and overs.")
    // fired even when two of the three were filled, so a scorer who had only
    // missed the opponent had to re-check every field to find it - and the
    // opponent dropdown is the one that silently stays empty when you have a
    // single team.
    final missing = <String>[
      if (_teamA == null) 'your team',
      if (_teamB == null) 'the opponent',
      if (overs == null) 'overs',
    ];
    if (missing.isNotEmpty || overs == null) {
      setState(() => _error = 'Still needed: ${missing.join(', ')}.');
      return;
    }
    if (_teamA == _teamB) {
      setState(() => _error = 'Teams must be different.');
      return;
    }
    // The Overs box is a bare numeric field, so 0 (or a mistyped 300) used to go
    // straight through: create_match now refuses it server-side, but say it here
    // rather than making the user round-trip to find out.
    if (overs < 1 || overs > 100) {
      setState(() => _error = 'Overs must be between 1 and 100.');
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
              "Let's set it up - watch it live once we start: "
              "${Routes.publicMatchUrl(id)}");
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
          _OpponentField(
            teamId: _teamB,
            excludeTeamId: _teamA,
            onPicked: (id, name) => setState(() {
              _teamB = id;
              _teamBName = name;
            }),
            knownName: _teamBName,
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
          // The reason a submit failed belongs ABOVE the button that produced
          // it. It used to render after, and the button is the last thing in a
          // long scrolling form - so on a phone the message landed off-screen
          // below the fold and tapping Post simply appeared to do nothing
          // (found by driving journey B, 2026-07-07).
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          FilledButton(
            onPressed: _busy ? null : _create,
            child: const Text('Next: squads'),
          ),
        ],
      ),
    );
  }
}

/// The opponent picker. Tapping opens a search sheet; with an empty box it
/// offers the clubs this user has actually played, which is the answer most of
/// the time. It replaced a DropdownButton fed by every team in the database.
class _OpponentField extends ConsumerWidget {
  const _OpponentField({
    required this.teamId,
    required this.excludeTeamId,
    required this.onPicked,
    this.knownName,
  });

  final String? teamId;
  final String? excludeTeamId;
  final String? knownName;
  final void Function(String id, String name) onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An opponent carried in from the discover bridge arrives as a bare id, so
    // resolve its name rather than showing the user a uuid.
    final resolved = knownName ??
        (teamId == null
            ? null
            : ref.watch(teamProvider(teamId!)).value?['name'] as String?);
    final chosen = teamId != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.shield_outlined),
      title: Text(
        chosen ? (resolved ?? 'Opponent selected') : 'Choose the opponent',
        style: chosen
            ? null
            : TextStyle(color: Theme.of(context).hintColor),
      ),
      trailing: const Icon(Icons.search),
      onTap: () async {
        final picked = await showModalBottomSheet<({String id, String name})>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _OpponentSearchSheet(excludeTeamId: excludeTeamId),
        );
        if (picked != null) onPicked(picked.id, picked.name);
      },
    );
  }
}

class _OpponentSearchSheet extends ConsumerStatefulWidget {
  const _OpponentSearchSheet({required this.excludeTeamId});

  final String? excludeTeamId;

  @override
  ConsumerState<_OpponentSearchSheet> createState() =>
      _OpponentSearchSheetState();
}

class _OpponentSearchSheetState extends ConsumerState<_OpponentSearchSheet> {
  final _q = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(opponentSearchProvider(
      (query: _query, excludeTeamId: widget.excludeTeamId),
    ));
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Opponent', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _q,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search teams',
              hintText: 'Type a club name',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          // A FIXED 320 plus the title, the field and the keyboard inset does
          // not fit a 375x667 phone once autofocus raises the keyboard - the
          // sheet overflowed (re-review 2026-07-07). Take what is actually
          // left, with a floor so it never collapses to nothing.
          SizedBox(
            height: () {
              final m = MediaQuery.of(context);
              final free = m.size.height - m.viewInsets.bottom - 220;
              return free.clamp(160.0, 320.0);
            }(),
            child: results.when(
              loading: () => const AppSkeletonList(rows: 5),
              error: (e, _) => Center(child: Text(humanError(e))),
              data: (rows) {
                if (rows.isEmpty) {
                  return AppEmpty(
                    icon: Icons.shield_outlined,
                    title: _query.trim().length < 2
                        ? 'No past opponents yet'
                        : 'No team called "${_query.trim()}"',
                    message: _query.trim().length < 2
                        ? 'Type a club name to find who you are playing.'
                        : 'Check the spelling, or ask them to create their team '
                            'on Pitch first.',
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = rows[i];
                    final city = t['city'] as String?;
                    final played = t['last_played'] != null;
                    return ListTile(
                      title: Text(t['name'] as String),
                      subtitle: Text([
                        if (city != null && city.isNotEmpty) city,
                        if (played) 'played before',
                      ].join(' - ')),
                      onTap: () => Navigator.of(context).pop(
                        (id: t['id'] as String, name: t['name'] as String),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
