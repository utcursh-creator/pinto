import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../data/discover_models.dart';
import '../data/discover_providers.dart';
import '../data/discover_repository.dart';
import 'flair_chip.dart';
import '../../../core/ui/human_error.dart';

class MyPostsScreen extends ConsumerWidget {
  const MyPostsScreen({super.key});

  /// 'Mark filled' and 'Cancel' used to fail COMPLETELY silently: no try, no
  /// message, and the row stayed exactly as it was, so the user tapped again and
  /// again with no idea the write was being rejected (penetration review
  /// 2026-07-07).
  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      ref.invalidate(myPostsProvider);
      ref.invalidate(discoverFeedProvider);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
          content: Text(humanError(e, fallback: 'Could not update the post.'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(myPostsProvider);
    final repo = ref.read(discoverRepositoryProvider);
    return AdaptiveScaffold(
      title: 'My posts',
      body: posts.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text(humanError(e, fallback: 'Could not load your posts.'))),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text("You haven't posted anything yet."))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final p = rows[i];
                  final id = p['id'] as String;
                  final status = p['status'] as String?;
                  final open = status == 'open';
                  return Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (p['title'] as String?) ??
                                LfLabels.mode(p['mode'] as String?),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              FlairChip(p['flair'] as String?),
                              const SizedBox(width: 8),
                              Chip(
                                label: Text(status ?? ''),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          if (open) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      _act(context, ref, () => repo.markFilled(id)),
                                  child: const Text('Mark filled'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _act(context, ref, () => repo.cancelPost(id)),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
