import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../discover/data/discover_providers.dart';
import '../../discover/data/discover_repository.dart';
import '../../identity/presentation/initials_avatar.dart';

/// The DM inbox: conversations newest-first with unread badges (DM-4), last
/// message time (DM-6), pull-to-refresh (DM-5), and a compose action that can
/// start a NEW conversation via a people search (DM-7).
class DmInboxScreen extends ConsumerWidget {
  const DmInboxScreen({super.key});

  /// DM-6: inbox row trailing time ("14:05" today, "3 Jul" otherwise).
  static String lastAtLabel(dynamic lastAt) {
    final dt = DateTime.tryParse(lastAt?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(dmInboxProvider);
    return AdaptiveScaffold(
      title: 'Messages',
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'New message',
          onPressed: () => _compose(context, ref),
        ),
      ],
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Could not load messages.\n$e')),
        data: (threads) => RefreshIndicator.adaptive(
          onRefresh: () async => ref.invalidate(dmInboxProvider),
          child: threads.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 200),
                  Center(child: Text('No conversations yet.')),
                ])
              : ListView.separated(
                  itemCount: threads.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = threads[i];
                    final other = t['other'] as Map<String, dynamic>?;
                    final name = (other?['display_name'] as String?) ?? 'Player';
                    final unread = (t['unread'] as int?) ?? 0;
                    return ListTile(
                      leading: InitialsAvatar(
                          name: name,
                          photoUrl: other?['photo_url'] as String?,
                          radius: 20),
                      title: Text(name,
                          style: unread > 0
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null),
                      subtitle: t['preview'] == null
                          ? null
                          : Text(
                              t['preview'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(lastAtLabel(t['last_at']),
                              style: Theme.of(context).textTheme.bodySmall),
                          if (unread > 0) ...[
                            const SizedBox(height: 4),
                            CircleAvatar(
                              radius: 9,
                              backgroundColor: const Color(0xFF0F6E56),
                              child: Text('$unread',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white)),
                            ),
                          ],
                        ],
                      ),
                      onTap: () => context
                          .push(Routes.dmThread(t['thread_id'] as String)),
                    );
                  },
                ),
        ),
      ),
    );
  }

  /// DM-7: start a new conversation - search a player by name, tap to open a
  /// thread with them (get_or_create_dm_thread enforces blocks + rate limit).
  Future<void> _compose(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _PeoplePickerSheet(),
    );
    if (picked == null || !context.mounted) return;
    try {
      final threadId = await ref
          .read(discoverRepositoryProvider)
          .getOrCreateDmThread(picked['id'] as String);
      ref.invalidate(dmInboxProvider);
      if (context.mounted) context.push(Routes.dmThread(threadId));
    } catch (e) {
      final raw = '$e';
      messenger?.showSnackBar(SnackBar(
          content: Text(raw.contains('cannot message')
              ? 'You cannot message this user.'
              : raw.contains('too many new conversations')
                  ? 'Too many new conversations - try again later.'
                  : 'Could not start the conversation: $raw')));
    }
  }
}

class _PeoplePickerSheet extends ConsumerStatefulWidget {
  const _PeoplePickerSheet();

  @override
  ConsumerState<_PeoplePickerSheet> createState() => _PeoplePickerSheetState();
}

class _PeoplePickerSheetState extends ConsumerState<_PeoplePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchProvider(_query));
    final players = [
      for (final r in results.value ?? const <Map<String, dynamic>>[])
        if (r['kind'] == 'player') r,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New message',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search a player by name',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            if (_query.trim().length < 2)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Type at least 2 letters.'),
              )
            else if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No players found.'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in players)
                      ListTile(
                        dense: true,
                        leading: InitialsAvatar(
                            name: p['name'] as String?,
                            photoUrl: p['photo_url'] as String?,
                            radius: 18),
                        title: Text((p['name'] as String?) ?? 'Player'),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
