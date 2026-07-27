import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../discover/data/discover_providers.dart';
import '../../discover/data/discover_repository.dart';
import '../../../core/ui/human_error.dart';

/// MISS-2: the in-app notifications inbox. Rows are written by backend triggers
/// (reply / dm / claim / invite-accepted / match-live); tapping routes to the
/// thing itself; opening the screen marks everything read.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Mark read on open; refresh the badge afterwards.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(discoverRepositoryProvider).markNotificationsRead();
        ref.invalidate(notificationsProvider);
      } catch (_) {/* non-fatal */}
    });
  }

  static IconData _icon(String? type) => switch (type) {
        'post_reply' => Icons.reply_outlined,
        'dm' => Icons.chat_bubble_outline,
        'claim_request' => Icons.how_to_reg_outlined,
        'join_request' => Icons.person_add_alt_outlined,
        'invite_accepted' => Icons.group_add_outlined,
        'match_live' => Icons.sensors,
        _ => Icons.notifications_none,
      };

  /// Where a row leads, or null if it leads nowhere. Returning null (rather
  /// than swallowing the tap) lets the list render the row as non-tappable:
  /// `claim_request` and `join_request` rows used to look exactly like every
  /// other row and do nothing at all when tapped, which reads as a broken app
  /// at the precise moment a captain is trying to act on a request.
  static String? _destination(Map<String, dynamic> n) {
    final refId = n['ref_id'] as String?;
    if (refId == null) return null;
    return switch (n['type'] as String?) {
      'post_reply' => Routes.postDetail(refId),
      'dm' => Routes.dmThread(refId),
      'match_live' => Routes.viewMatch(refId),
      'invite_accepted' => Routes.teamPage(refId),
      // ref_id is the membership row; the captain reviews claims in the inbox.
      'claim_request' => Routes.claimInbox,
      // ref_id is the team; join requests are reviewed on the team page.
      'join_request' => Routes.teamPage(refId),
      _ => null,
    };
  }

  static String _when(dynamic createdAt) {
    final dt = DateTime.tryParse(createdAt?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    return AdaptiveScaffold(
      title: 'Notifications',
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text(humanError(e, fallback: 'Could not load notifications.'))),
        data: (rows) => RefreshIndicator.adaptive(
          onRefresh: () async => ref.invalidate(notificationsProvider),
          child: rows.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 200),
                  Center(child: Text('Nothing yet - go find a game.')),
                ])
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final n = rows[i];
                    final unread = n['read_at'] == null;
                    final dest = _destination(n);
                    return ListTile(
                      leading: Icon(_icon(n['type'] as String?),
                          color: unread ? const Color(0xFF0F6E56) : null),
                      title: Text(
                        (n['body'] as String?) ?? '',
                        style: unread
                            ? const TextStyle(fontWeight: FontWeight.w600)
                            : null,
                      ),
                      subtitle: Text(_when(n['created_at']),
                          style: Theme.of(context).textTheme.bodySmall),
                      // A row that goes somewhere says so; one that does not
                      // stays inert rather than faking a tap target.
                      trailing: dest == null
                          ? null
                          : const Icon(Icons.chevron_right, size: 18),
                      onTap: dest == null ? null : () => context.push(dest),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
