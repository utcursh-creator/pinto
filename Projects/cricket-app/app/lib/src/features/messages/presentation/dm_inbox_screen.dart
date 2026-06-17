import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../discover/data/discover_providers.dart';
import '../../identity/presentation/initials_avatar.dart';

class DmInboxScreen extends ConsumerWidget {
  const DmInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(dmInboxProvider);
    return AdaptiveScaffold(
      title: 'Messages',
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Could not load messages.\n$e')),
        data: (threads) => threads.isEmpty
            ? const Center(child: Text('No conversations yet.'))
            : ListView.separated(
                itemCount: threads.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = threads[i];
                  final other = t['other'] as Map<String, dynamic>?;
                  final name = (other?['display_name'] as String?) ?? 'Player';
                  return ListTile(
                    leading: InitialsAvatar(name: name, radius: 20),
                    title: Text(name),
                    subtitle: t['preview'] == null
                        ? null
                        : Text(
                            t['preview'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () =>
                        context.push(Routes.dmThread(t['thread_id'] as String)),
                  );
                },
              ),
      ),
    );
  }
}
