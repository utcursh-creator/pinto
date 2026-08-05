import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../data/discover_models.dart';
import '../data/discover_providers.dart';
import '../data/discover_repository.dart';
import 'flair_chip.dart';
import '../../../core/ui/human_error.dart';
import '../../../core/platform/error_retry.dart';

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

  /// "Expires today" / "Expires in 3 days" - a post with a life span has to
  /// show it, or the author cannot tell a quiet week from a dead ad.
  static String _expiryLabel(DateTime expiresAt) {
    // ROUNDED UP: a post that dies in 71 hours has "2 days" left by integer
    // division, which reads as a day less than the author actually has.
    final days = (expiresAt.difference(DateTime.now()).inMinutes / 1440).ceil();
    if (days <= 0) return 'Expires today';
    return 'Expires in $days ${days == 1 ? 'day' : 'days'}';
  }

  /// A post whose match date has passed needs a NEW date: the feed floors on
  /// match_at, so more expiry time alone would leave it invisible and the
  /// author none the wiser. Undated ads just get their fortnight back.
  Future<void> _renew(BuildContext context, WidgetRef ref, String id,
      DateTime? matchAt) async {
    DateTime? newDate;
    final needsDate = matchAt != null &&
        matchAt.isBefore(DateTime.now().subtract(const Duration(hours: 6)));
    if (needsDate) {
      final picked = await showDatePicker(
        context: context,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 180)),
        initialDate: DateTime.now().add(const Duration(days: 7)),
        helpText: 'When is the new game?',
      );
      if (picked == null) return;
      newDate = DateTime(picked.year, picked.month, picked.day,
          matchAt.hour, matchAt.minute);
    }
    if (!context.mounted) return;
    await _act(
      context,
      ref,
      () => ref
          .read(discoverRepositoryProvider)
          .renewPost(id, matchAt: newDate),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(myPostsProvider);
    final repo = ref.read(discoverRepositoryProvider);
    return AdaptiveScaffold(
      title: 'My posts',
      body: posts.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => ErrorRetry(
          message: humanError(e, fallback: 'Could not load your posts.'),
          onRetry: () => ref.invalidate(myPostsProvider),
        ),
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
                  // An ad that ran out is invisible to everyone else, and used
                  // to read exactly like a live one - "open", with Mark filled
                  // and Cancel, and no expiry anywhere (review #2, finding 43).
                  final expiresAt =
                      DateTime.tryParse('${p['expires_at'] ?? ''}')?.toLocal();
                  final expired =
                      open && expiresAt != null && expiresAt.isBefore(DateTime.now());
                  final matchAt =
                      DateTime.tryParse('${p['match_at'] ?? ''}')?.toLocal();
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
                                label: Text(expired ? 'Expired' : (status ?? '')),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          if (expired)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'Nobody can see this any more.',
                                style: TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                            )
                          else if (open && expiresAt != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _expiryLabel(expiresAt),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                            ),
                          if (open) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (expired)
                                  TextButton(
                                    onPressed: () => _renew(
                                        context, ref, id, matchAt),
                                    child: const Text('Renew'),
                                  ),
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
