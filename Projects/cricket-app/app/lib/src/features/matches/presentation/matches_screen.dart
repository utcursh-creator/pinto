import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/platform/platform.dart';
import '../../../core/routing/routes.dart';
import '../../scoring/data/match_providers.dart';

class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(myMatchesProvider);
    final cupertino = isCupertino(context);
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
        error: (e, _) => Center(child: Text('Could not load matches.\n$e')),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('No matches yet. Start one.'))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final m = rows[i];
                  final id = m['id'] as String;
                  final status = m['status'] as String?;
                  final finished = status == 'complete' || status == 'abandoned';
                  final started = status != 'setup' && status != null;
                  return ListTile(
                    leading: const Icon(Icons.sports_cricket),
                    title: Text('${m['overs_limit']}-over match'),
                    subtitle: Text(
                      '${status ?? ''}'
                      '${m['venue'] != null ? '  -  ${m['venue']}' : ''}',
                    ),
                    trailing: started
                        ? IconButton(
                            icon: const Icon(Icons.visibility_outlined),
                            tooltip: 'Watch',
                            onPressed: () =>
                                context.push(Routes.viewMatch(id)),
                          )
                        : const Icon(Icons.chevron_right),
                    // Finished matches can't be scored: open the read-only view.
                    onTap: () => context.push(
                      finished ? Routes.viewMatch(id) : Routes.scoreMatch(id),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
