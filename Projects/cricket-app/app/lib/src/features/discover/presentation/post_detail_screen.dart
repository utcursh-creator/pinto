import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/discover_models.dart';
import '../data/discover_providers.dart';
import '../data/discover_repository.dart';
import 'flair_chip.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({required this.postId, super.key});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(discoverRepositoryProvider).reply(widget.postId, body);
      _reply.clear();
      ref.invalidate(postRepliesProvider(widget.postId));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _messageAuthor(String authorId) async {
    // DM-2: an anonymous viewer can't DM - route them to sign in instead of
    // silently swallowing the RPC's 'not authenticated'.
    if (ref.read(isAnonymousProvider)) {
      context.push(Routes.signIn);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final threadId = await ref
          .read(discoverRepositoryProvider)
          .getOrCreateDmThread(authorId);
      if (mounted) context.push(Routes.dmThread(threadId));
    } catch (e) {
      final raw = '$e';
      messenger?.showSnackBar(SnackBar(
          content: Text(raw.contains('cannot message')
              ? 'You cannot message this user.'
              : 'Could not open the conversation: $raw')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));
    final replies = ref.watch(postRepliesProvider(widget.postId));
    final me = ref.watch(currentSessionProvider)?.user.id;

    return AdaptiveScaffold(
      title: 'Post',
      body: post.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Could not load post.\n$e')),
        data: (p) {
          if (p == null) return const Center(child: Text('Post not found.'));
          final authorName = p['author_name'] as String?;
          final teamName = p['team_name'] as String?;
          final authorId = p['author_id'] as String?;
          final isMine = authorId != null && authorId == me;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      (p['title'] as String?)?.trim().isNotEmpty ?? false
                          ? p['title'] as String
                          : LfLabels.mode(p['mode'] as String?),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FlairChip(p['flair'] as String?),
                        // DISC-6: show the mode label only when it isn't the title.
                        if ((p['title'] as String?)?.trim().isNotEmpty ?? false) ...[
                          const SizedBox(width: 8),
                          Text(LfLabels.mode(p['mode'] as String?)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Posted by ${authorName ?? 'a player'}'
                      '${teamName != null ? ' ($teamName)' : ''}'
                      '${p['place_label'] != null ? '  -  ${p['place_label']}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    // DISC-2: the cricket metadata.
                    Builder(builder: (context) {
                      final chips = LfLabels.metaChips(
                        overs: (p['overs'] as num?)?.toInt(),
                        skillLevel: p['skill'] as String?,
                        slotsNeeded: (p['slots_needed'] as num?)?.toInt(),
                        matchAt: p['match_at'],
                      );
                      if (chips.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in chips)
                              Chip(
                                label: Text(c),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                      );
                    }),
                    if ((p['description'] as String?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 12),
                      Text(p['description'] as String),
                    ],
                    for (final url
                        in ((p['image_urls'] as List?) ?? const [])
                            .cast<String>()) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(url),
                      ),
                    ],
                    if ((p['link_url'] as String?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => launchUrl(
                          Uri.parse(p['link_url'] as String),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.link, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                p['link_url'] as String,
                                style: const TextStyle(color: Color(0xFF0F6E56)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!isMine) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: authorId == null
                            ? null
                            : () => _messageAuthor(authorId),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Message'),
                      ),
                      // Keystone bridge: turn a team-seeking-opponent post into a
                      // real match, carrying the poster's team in as the opponent.
                      if (p['mode'] == 'team_seeking_opponent' &&
                          p['team_id'] != null) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => context.push(
                            Routes.proposeMatch(
                              p['team_id'] as String,
                              overs: (p['overs'] as num?)?.toInt(),
                              authorId: authorId,
                            ),
                          ),
                          icon: const Icon(Icons.sports_cricket),
                          label: const Text('Propose a match'),
                        ),
                      ],
                    ],
                    const Divider(height: 32),
                    Text('Replies', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    replies.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(8),
                        child: Center(child: CircularProgressIndicator.adaptive()),
                      ),
                      error: (e, _) => Text('Could not load replies.\n$e'),
                      data: (rows) => rows.isEmpty
                          ? const Text('No replies yet. Be the first.')
                          : Column(
                              children: [
                                for (final r in rows)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      ((r['profiles'] as Map?)?['display_name']
                                              as String?) ??
                                          'Player',
                                      style: Theme.of(context).textTheme.labelLarge,
                                    ),
                                    subtitle: Text(r['body'] as String),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _reply,
                          decoration: const InputDecoration(
                            hintText: 'Write a reply...',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sending ? null : _sendReply,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
