import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/platform/platform.dart';
import '../../../core/routing/routes.dart';
import '../data/tournament_models.dart';
import '../data/tournament_providers.dart';

/// All tournaments. Tapping a card opens the public page; the organizer of a
/// tournament also gets a Manage shortcut.
class TournamentsListScreen extends ConsumerWidget {
  const TournamentsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tournamentsListProvider);
    final me = ref.watch(currentSessionProvider)?.user.id;
    final cupertino = isCupertino(context);

    return AdaptiveScaffold(
      title: 'Tournaments',
      actions: [
        IconButton(
          icon: const Icon(Icons.vpn_key_outlined),
          tooltip: 'Join with a code',
          onPressed: () => _joinWithCode(context),
        ),
        if (cupertino)
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push(Routes.newTournament),
          ),
      ],
      floatingActionButton: cupertino
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(Routes.newTournament),
              icon: const Icon(Icons.add),
              label: const Text('Create tournament'),
            ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Could not load tournaments.\n$e')),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('No tournaments yet. Create one.'))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = rows[i];
                  final id = t['id'] as String;
                  final mine = me != null && t['organizer_id'] == me;
                  final champion = t['champion_team_id'] != null;
                  return ListTile(
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: Text((t['name'] as String?) ?? 'Tournament'),
                    subtitle: Row(
                      children: [
                        _StatusChip(status: t['status'] as String?),
                        if (t['city'] != null) ...[
                          const SizedBox(width: 8),
                          Text(t['city'] as String,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                        if (champion) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.emoji_events,
                              size: 14, color: Theme.of(context).colorScheme.primary),
                        ],
                      ],
                    ),
                    trailing: mine
                        ? TextButton(
                            onPressed: () =>
                                context.push(Routes.manageTournament(id)),
                            child: const Text('Manage'),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.tournamentPage(id)),
                  );
                },
              ),
      ),
    );
  }

  // In-app fallback for the tournament join link (no hosted web domain yet, so
  // a shared https link won't resolve in a browser - the code carries the token).
  Future<void> _joinWithCode(BuildContext context) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a tournament'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Invite code',
            hintText: 'Paste the code the organizer shared',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    // Accept either a raw code or a full join link.
    final token = code.contains('/join-tournament/')
        ? code.split('/join-tournament/').last.trim()
        : code;
    context.push(Routes.joinTournament(token));
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(tournamentStatusLabel(status),
          style: theme.textTheme.labelSmall),
    );
  }
}
