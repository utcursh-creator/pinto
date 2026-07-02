import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../discover/data/discover_providers.dart';
import '../../discover/data/discover_repository.dart';

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
        'invite_accepted' => Icons.group_add_outlined,
        'match_live' => Icons.sensors,
        _ => Icons.notifications_none,
      };

  void _open(BuildContext context, Map<String, dynamic> n) {
    final ref_ = n['ref_id'] as String?;
    if (ref_ == null) return;
    switch (n['type'] as String?) {
      case 'post_reply':
        context.push(Routes.postDetail(ref_));
      case 'dm':
        context.push(Routes.dmThread(ref_));
      case 'match_live':
        context.push(Routes.viewMatch(ref_));
      case 'invite_accepted':
        context.push(Routes.teamPage(ref_));
      default:
        break; // claim_request reviews happen on the team page roster
    }
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
        error: (e, _) => Center(child: Text('Could not load notifications.\n$e')),
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
                    return ListTile(
                      leading: Icon(_icon(n['type'] as String?),
                          color: unread ? const Color(0xFF0F6E56) : null),
                      title: Text(
                        (n['body'] as String?) ?? '',
                        style: unread
                            ? const TextStyle(fontWeight: FontWeight.w600)
                            : null,
                      ),
                      trailing: Text(_when(n['created_at']),
                          style: Theme.of(context).textTheme.bodySmall),
                      onTap: () => _open(context, n),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
