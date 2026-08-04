import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../identity/data/identity_repository.dart';
import '../../scoring/data/match_repository.dart';
import '../data/tournament_models.dart';
import '../data/tournament_providers.dart';
import '../data/tournament_repository.dart';
import '../../../core/ui/human_error.dart';
import '../../../core/platform/error_retry.dart';
import '../../../core/platform/share.dart';

/// Organizer hub. What's shown follows the tournament status: assign teams to
/// groups + generate fixtures (setup) -> score group matches + generate playoffs
/// (group_stage) -> score the bracket + advance to the champion (playoffs).
class ManageTournamentScreen extends ConsumerWidget {
  const ManageTournamentScreen({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tournamentOverviewProvider(tournamentId));
    return AdaptiveScaffold(
      title: 'Manage tournament',
      actions: [
        IconButton(
          icon: const Icon(Icons.visibility_outlined),
          tooltip: 'Public page',
          onPressed: () => context.push(Routes.tournamentPage(tournamentId)),
        ),
      ],
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => ErrorRetry(
          message: humanError(e, fallback: 'Could not load this tournament.'),
          onRetry: () => ref.invalidate(tournamentOverviewProvider(tournamentId)),
        ),
        data: (o) => ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _Header(info: o.info),
            const Divider(height: 1),
            ...switch (o.info.status) {
              'setup' => _setup(context, ref, o),
              'group_stage' => _groupStage(context, ref, o),
              'playoffs' => _playoffs(context, ref, o),
              _ => _complete(context, o),
            },
          ],
        ),
      ),
    );
  }

  // ---- setup: teams -> groups + generate fixtures ----
  List<Widget> _setup(BuildContext context, WidgetRef ref, TournamentOverview o) {
    final byGroup = <String, int>{'A': 0, 'B': 0};
    for (final t in o.teams) {
      byGroup[t.groupLabel] = (byGroup[t.groupLabel] ?? 0) + 1;
    }
    final canGenerate = (byGroup['A'] ?? 0) >= 2 && (byGroup['B'] ?? 0) >= 2;
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text('Teams', style: TextStyle(fontWeight: FontWeight.w500)),
      ),
      for (final t in o.teams)
        ListTile(
          dense: true,
          title: Text(t.name),
          trailing: Wrap(spacing: 6, children: [
            for (final g in const ['A', 'B'])
              ChoiceChip(
                label: Text(g),
                selected: t.groupLabel == g,
                onSelected: (_) => _setGroup(context, ref, t.teamId, g),
              ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addTeam(context, ref, o),
                icon: const Icon(Icons.add),
                label: const Text('Add my team'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _inviteTeam(context, ref),
                icon: const Icon(Icons.link),
                label: const Text('Invite a team'),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: FilledButton(
          onPressed: canGenerate ? () => _run(context, ref, (r) => r.generateGroupFixtures(tournamentId)) : null,
          child: const Text('Generate group fixtures'),
        ),
      ),
      if (!canGenerate)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            // Naming the REAL requirement. "Add at least 2 teams to each group"
            // is true but unactionable: the v1 format is 2 groups with the top 2
            // of each qualifying, so the minimum is FOUR teams - and nothing
            // told the organizer that until they were already stuck (seen on the
            // simulator, fix run 2026-07-07). Now it also shows where they are.
            'You need 4 teams to start: 2 in group A and 2 in group B. '
            'Right now A has ${byGroup['A'] ?? 0} and B has ${byGroup['B'] ?? 0}.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
    ];
  }

  // ---- group stage: score group matches + generate playoffs ----
  List<Widget> _groupStage(BuildContext context, WidgetRef ref, TournamentOverview o) {
    final group = o.fixturesForStage('group');
    final allDone = group.isNotEmpty && group.every((f) => f.isComplete);
    return [
      _fixtureSection(context, ref, 'Group fixtures', group),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: FilledButton(
          onPressed: allDone ? () => _run(context, ref, (r) => r.generatePlayoffs(tournamentId)) : null,
          child: const Text('Generate playoffs'),
        ),
      ),
      if (!allDone)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('Finish every group match to seed the semifinals.',
              style: TextStyle(fontSize: 12)),
        ),
    ];
  }

  // ---- playoffs: score the bracket + advance ----
  List<Widget> _playoffs(BuildContext context, WidgetRef ref, TournamentOverview o) {
    final semis = o.fixturesForStage('semifinal');
    final fin = o.fixturesForStage('final');
    final semisDone = semis.isNotEmpty && semis.every((f) => f.isComplete);
    final finalDone = fin.isNotEmpty && fin.every((f) => f.isComplete);
    final label = fin.isEmpty ? 'Advance to final' : 'Crown the champion';
    final canAdvance = fin.isEmpty ? semisDone : finalDone;
    return [
      _fixtureSection(context, ref, 'Semifinals', semis),
      if (fin.isNotEmpty) _fixtureSection(context, ref, 'Final', fin),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: FilledButton(
          onPressed: canAdvance ? () => _run(context, ref, (r) => r.advancePlayoffs(tournamentId)) : null,
          child: Text(label),
        ),
      ),
    ];
  }

  List<Widget> _complete(BuildContext context, TournamentOverview o) => [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(children: [
              Icon(Icons.emoji_events,
                  size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              const Text('Tournament complete'),
              TextButton(
                onPressed: () => context.push(Routes.tournamentPage(tournamentId)),
                child: const Text('View public page'),
              ),
            ]),
          ),
        ),
      ];

  Widget _fixtureSection(BuildContext context, WidgetRef ref, String title,
      List<Fixture> fixtures) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      ),
      for (final f in fixtures)
        ListTile(
          dense: true,
          title: Text('${f.teamA}  v  ${f.teamB}'),
          // statusLine now carries the scoreline + winner for completed matches.
          subtitle: Text([
            if (f.groupLabel != null) 'Group ${f.groupLabel}',
            // TOUR-4: show the schedule the organizer set
            if (f.scheduleLine.isNotEmpty) f.scheduleLine,
            f.statusLine,
          ].join('  -  ')),
          trailing: f.isComplete
              ? const Text('Done')
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  // TOUR-4: organizer sets/edits the fixture's date + ground
                  if (!f.isLive)
                    IconButton(
                      icon: const Icon(Icons.event_outlined, size: 20),
                      tooltip: 'Schedule',
                      onPressed: () => _editSchedule(context, ref, f),
                    ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () => context.push(_fixtureDest(f)),
                    // TOUR-1: a fresh fixture has no squads yet - start the
                    // setup wizard, don't dead-end at the empty console.
                    child: Text(f.isUpcoming ? 'Set up' : 'Score'),
                  ),
                ]),
          onTap: () => context.push(_fixtureDest(f)),
        ),
    ]);
  }

  /// TOUR-4: date + venue editor for a fixture (update_match_schedule RPC).
  Future<void> _editSchedule(
      BuildContext context, WidgetRef ref, Fixture f) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final venueCtrl = TextEditingController(text: f.venue ?? '');
    DateTime? when = f.scheduledAt?.toLocal();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${f.teamA}  v  ${f.teamB}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(when == null
                      ? 'Pick date & time'
                      : '${when!.day}/${when!.month}/${when!.year} '
                          '${when!.hour.toString().padLeft(2, '0')}:'
                          '${when!.minute.toString().padLeft(2, '0')}'),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: when ?? now,
                      firstDate: now.subtract(const Duration(days: 30)),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (d == null || !ctx.mounted) return;
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(when ?? now),
                    );
                    setSheet(() => when = DateTime(
                        d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
                  },
                ),
                TextField(
                  controller: venueCtrl,
                  decoration: const InputDecoration(labelText: 'Ground / venue'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save schedule'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true) return;
    try {
      await ref.read(matchRepositoryProvider).updateMatchSchedule(
            matchId: f.matchId,
            scheduledAt: when,
            venue: venueCtrl.text.trim(),
          );
      ref.invalidate(tournamentOverviewProvider(tournamentId));
    } catch (e) {
      messenger?.showSnackBar(
          SnackBar(content: Text(humanError(e, fallback: 'Could not save the schedule.'))));
    }
  }

  /// Where tapping a fixture goes: a fresh (setup) fixture -> the squad wizard
  /// (TOUR-1); a live one -> the console; a finished one -> the read-only view.
  String _fixtureDest(Fixture f) => f.isComplete
      ? Routes.viewMatch(f.matchId)
      : f.isUpcoming
          ? Routes.matchSquads(f.matchId)
          : Routes.scoreMatch(f.matchId);

  /// Moves a team between groups. Uses set_tournament_team_group, NOT
  /// add_tournament_team: the latter's SEC-8 consent gate (is_team_admin of the
  /// team) is unsatisfiable for the organizer when the team joined by invite, so
  /// every chip tap raised 'you must be an admin of this team to enter it' - and
  /// this method used to swallow it, leaving invite-built tournaments unable to
  /// ever reach two populated groups (penetration review 2026-07-07).
  Future<void> _setGroup(
      BuildContext context, WidgetRef ref, String teamId, String group) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(tournamentRepositoryProvider)
          .setTournamentTeamGroup(tournamentId, teamId, group);
      ref.invalidate(tournamentOverviewProvider(tournamentId));
    } catch (e) {
      messenger?.showSnackBar(
          SnackBar(content: Text('Could not move the team to group $group.')));
    }
  }

  /// HIGH (review #2, finding 9): every await in here used to be unguarded.
  ///
  /// The list came from myTeamsProvider, which returns every team the organiser
  /// BELONGS to with no role filter, while add_tournament_team raises 'you must
  /// be an admin of this team to enter it'. That throw landed in a tap callback
  /// with no try/catch, so there was no SnackBar, no team added and no
  /// invalidate - the organiser taps the same club repeatedly and concludes the
  /// app is broken. Offline, the team-list read threw first and the button
  /// simply did nothing at all.
  Future<void> _addTeam(BuildContext context, WidgetRef ref, TournamentOverview o) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final List<Map<String, dynamic>> myTeams;
    try {
      // The REPOSITORY, not `ref.read(myTeamsProvider.future)`: this screen
      // does not watch that provider, and the list is wanted as of the tap
      // anyway (a club joined on another device should show up).
      myTeams = await ref.read(identityRepositoryProvider).myTeams();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
          content: Text(humanError(e, fallback: 'Could not load your teams.'))));
      return;
    }
    final existing = o.teams.map((t) => t.teamId).toSet();
    final options = [
      for (final r in myTeams)
        // Only teams this organiser can actually enter. Offering the rest can
        // only ever end in a refusal from the server.
        if (r['teams'] != null &&
            (r['role'] == 'captain' || r['role'] == 'admin') &&
            !existing.contains((r['teams'] as Map)['id']))
          r['teams'] as Map<String, dynamic>,
    ];
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: options.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('No more teams to add.'))
            : ListView(shrinkWrap: true, children: [
                const ListTile(title: Text('Add a team')),
                for (final t in options)
                  ListTile(
                    title: Text((t['name'] as String?) ?? 'Team'),
                    onTap: () => Navigator.pop(ctx, t['id'] as String),
                  ),
              ]),
      ),
    );
    if (picked != null) {
      try {
        await ref
            .read(tournamentRepositoryProvider)
            .addTournamentTeam(tournamentId, picked, 'A');
        ref.invalidate(tournamentOverviewProvider(tournamentId));
      } catch (e) {
        messenger?.showSnackBar(SnackBar(
            content:
                Text(humanError(e, fallback: 'Could not add that team.'))));
      }
    }
  }

  // SEC-8: invite a team the organizer does NOT manage. Mints a join token and
  // shares it; a captain of that team redeems it (their consent), mirroring
  // CricHeroes' tournament invite link / PIN.
  Future<void> _inviteTeam(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final token = await ref
          .read(tournamentRepositoryProvider)
          .createTournamentInvite(tournamentId);
      if (!context.mounted) return;
      await shareFrom(
        context,
        text: 'Add your team to my cricket tournament on Pitch: '
            '${joinTournamentLink(token)}\nOr enter this code in the app: $token',
        subject: 'Pitch tournament invite',
      );
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
  }

  Future<void> _run(BuildContext context, WidgetRef ref,
      Future<void> Function(TournamentRepository) action) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action(ref.read(tournamentRepositoryProvider));
      ref.invalidate(tournamentOverviewProvider(tournamentId));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(humanError(e))));
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.info});
  final TournamentInfo info;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(children: [
        Expanded(
            child: Text(info.name,
                style: Theme.of(context).textTheme.titleLarge)),
        Text(info.statusLabel, style: Theme.of(context).textTheme.labelMedium),
      ]),
    );
  }
}
