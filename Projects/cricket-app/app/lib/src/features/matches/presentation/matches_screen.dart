import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/platform/platform.dart';
import '../../../core/routing/routes.dart';
import '../../identity/data/identity_providers.dart';
import '../../scoring/data/match_providers.dart';
import '../../scoring/data/match_repository.dart';
import '../../../core/ui/human_error.dart';
import '../../../core/platform/error_retry.dart';

class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(myMatchesProvider);
    final cupertino = isCupertino(context);
    final myId = ref.watch(currentSessionProvider)?.user.id;
    return AdaptiveScaffold(
      title: 'Matches',
      actions: [
        IconButton(
          icon: const Icon(Icons.emoji_events_outlined),
          tooltip: 'Tournaments',
          onPressed: () => context.push(Routes.tournaments),
        ),
        IconButton(
          icon: const Icon(Icons.sensors),
          tooltip: 'Watch live',
          onPressed: () => context.push(Routes.liveMatches),
        ),
        if (cupertino)
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push(Routes.startMatch),
          ),
      ],
      floatingActionButton: cupertino
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(Routes.startMatch),
              icon: const Icon(Icons.add),
              label: const Text('Start a match'),
            ),
      body: matches.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => ErrorRetry(
          message: humanError(e, fallback: 'Could not load matches.'),
          onRetry: () => ref.invalidate(myMatchesProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(child: Text('No matches yet. Start one.'));
          }
          // Split into Live / Upcoming / Completed (each already newest-first).
          final live = <Map<String, dynamic>>[];
          final upcoming = <Map<String, dynamic>>[];
          final completed = <Map<String, dynamic>>[];
          for (final m in rows) {
            switch (m['status'] as String?) {
              case 'live':
              case 'innings_break':
                live.add(m);
              case 'complete':
              case 'abandoned':
                completed.add(m);
              default:
                upcoming.add(m);
            }
          }
          return RefreshIndicator.adaptive(
            onRefresh: () async => ref.invalidate(myMatchesProvider),
            child: ListView(
              children: [
                ..._section(context, ref, 'Live', live, myId),
                ..._section(context, ref, 'Upcoming', upcoming, myId),
                ..._section(context, ref, 'Completed', completed, myId),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<Map<String, dynamic>> rows,
    String? myId,
  ) {
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      ),
      for (final m in rows) _MatchTile(row: m, myId: myId),
      const Divider(height: 1),
    ];
  }
}

class _MatchTile extends ConsumerWidget {
  const _MatchTile({required this.row, required this.myId});

  final Map<String, dynamic> row;
  final String? myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = row['id'] as String;
    final status = row['status'] as String?;
    final finished = status == 'complete' || status == 'abandoned';
    final started = status != 'setup' && status != null;
    final isOwner = myId != null && row['owner_id'] == myId;

    final a = embeddedTeamName(row['team_a']);
    final b = embeddedTeamName(row['team_b']);
    final resultLine = matchResultLine(row);
    final sub = finished
        ? (resultLine ?? 'Completed')
        : status == 'live'
            ? 'Live now'
            : status == 'innings_break'
                ? 'Innings break'
                : 'Setup - not started'
                    '${row['venue'] != null ? '  -  ${row['venue']}' : ''}';

    return ListTile(
      leading: Icon(
        finished ? Icons.emoji_events_outlined : Icons.sports_cricket,
        color: status == 'live' ? Colors.red : null,
      ),
      title: Text('$a  v  $b'),
      subtitle: Text('${row['overs_limit']}-over match  -  $sub'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _onAction(context, ref, v),
        itemBuilder: (context) => [
          if (finished)
            const PopupMenuItem(value: 'view', child: Text('View scorecard'))
          else if (started)
            const PopupMenuItem(value: 'score', child: Text('Continue scoring'))
          else
            const PopupMenuItem(value: 'resume', child: Text('Resume setup')),
          if (started && !finished)
            const PopupMenuItem(value: 'watch', child: Text('Watch (public)')),
          if (!finished)
            const PopupMenuItem(value: 'abandon', child: Text('Abandon match')),
          if (isOwner)
            const PopupMenuItem(value: 'delete', child: Text('Delete match')),
        ],
      ),
      onTap: () => context.push(
        finished
            ? Routes.viewMatch(id)
            : started
                ? Routes.scoreMatch(id)
                : Routes.matchSquads(id),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, String v) async {
    final id = row['id'] as String;
    switch (v) {
      case 'view':
      case 'watch':
        context.push(Routes.viewMatch(id));
      case 'score':
        context.push(Routes.scoreMatch(id));
      case 'resume':
        context.push(Routes.matchSquads(id));
      case 'abandon':
        await _confirmAndRun(
          context,
          ref,
          title: 'Abandon this match?',
          body: 'It will be marked abandoned with no result. This cannot be undone.',
          action: 'Abandon',
          run: () => ref
              .read(matchRepositoryProvider)
              .setResult(matchId: id, resultType: 'abandoned'),
        );
      case 'delete':
        await _confirmAndRun(
          context,
          ref,
          title: 'Delete this match?',
          body: 'The match and all its scoring will be permanently removed.',
          action: 'Delete',
          destructive: true,
          run: () => ref.read(matchRepositoryProvider).deleteMatch(id),
        );
    }
  }

  Future<void> _confirmAndRun(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String body,
    required String action,
    required Future<void> Function() run,
    bool destructive = false,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: Colors.red)
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await run();
      // Every cache that describes this match, not just the list in front of
      // us (review #2, finding 34). None of these are autoDispose, so the row
      // fetched when the console was opened is held for the whole session: the
      // viewer would keep rendering the red LIVE badge with no result, the Info
      // tab would say "Status: live", and Watch-live would keep listing an
      // abandoned game. The viewer's realtime re-fold cannot save it - it
      // subscribes when opened, long after the UPDATE broadcast fired.
      ref.invalidate(myMatchesProvider);
      ref.invalidate(matchProvider);
      ref.invalidate(liveMatchesProvider);
      ref.invalidate(teamMatchesProvider);
      messenger?.showSnackBar(SnackBar(content: Text('$action done.')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(humanError(e, fallback: 'Could not $action.'))));
    }
  }
}
