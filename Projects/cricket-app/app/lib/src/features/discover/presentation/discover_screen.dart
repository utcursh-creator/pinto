import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/platform/platform.dart';
import '../../../core/routing/routes.dart';
import '../data/discover_models.dart';
import '../data/discover_providers.dart';
import 'flair_chip.dart';

/// The headline screen: a geo-targeted feed of looking-for posts near the
/// anchor, filterable by mode + flair, with reply / message actions.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  String? _mode;
  String? _flair;

  @override
  Widget build(BuildContext context) {
    final anchor = ref.watch(anchorProvider);
    final query = DiscoverQuery(
      lat: anchor.lat,
      lng: anchor.lng,
      radiusM: anchor.radiusM,
      mode: _mode,
      flair: _flair,
    );
    final feed = ref.watch(discoverFeedProvider(query));
    final cupertino = isCupertino(context);

    return AdaptiveScaffold(
      title: 'Discover',
      actions: [
        IconButton(
          icon: const Icon(Icons.mail_outline),
          onPressed: () => context.push(Routes.messages),
        ),
        IconButton(
          icon: const Icon(Icons.tune),
          onPressed: () => context.push(Routes.myPosts),
        ),
        if (cupertino)
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push(Routes.compose),
          ),
      ],
      floatingActionButton: cupertino
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(Routes.compose),
              icon: const Icon(Icons.add),
              label: const Text('New post'),
            ),
      body: Column(
        children: [
          _FilterBar(
            mode: _mode,
            flair: _flair,
            onMode: (m) => setState(() => _mode = m),
            onFlair: (f) => setState(() => _flair = f),
            onLocation: () => context.push(Routes.location),
          ),
          Expanded(
            child: feed.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) => Center(child: Text('Could not load the feed.\n$e')),
              data: (posts) => posts.isEmpty
                  ? const Center(child: Text('No open posts nearby yet.'))
                  : RefreshIndicator.adaptive(
                      onRefresh: () async =>
                          ref.invalidate(discoverFeedProvider(query)),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: posts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _PostCard(post: posts[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.mode,
    required this.flair,
    required this.onMode,
    required this.onFlair,
    required this.onLocation,
  });

  final String? mode;
  final String? flair;
  final ValueChanged<String?> onMode;
  final ValueChanged<String?> onFlair;
  final VoidCallback onLocation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onLocation,
              icon: const Icon(Icons.place_outlined, size: 18),
              label: const Text('Near me'),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: mode == null,
                  onSelected: (_) => onMode(null),
                ),
                const SizedBox(width: 6),
                for (final e in LfLabels.modes.entries) ...[
                  ChoiceChip(
                    label: Text(e.value),
                    selected: mode == e.key,
                    onSelected: (_) => onMode(e.key),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = (post['title'] as String?) ??
        LfLabels.mode(post['mode'] as String?);
    final desc = post['description'] as String?;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.push(Routes.postDetail(post['post_id'] as String)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    LfLabels.distance(post['approx_m'] as num?),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  FlairChip(post['flair'] as String?),
                  const SizedBox(width: 8),
                  Text(
                    LfLabels.mode(post['mode'] as String?),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (desc != null && desc.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
