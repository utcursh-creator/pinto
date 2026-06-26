import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/platform/platform.dart';
import '../../../core/routing/routes.dart';
import '../data/discover_models.dart';
import '../data/discover_providers.dart';
import 'flair_chip.dart';

int _imageCount(Map<String, dynamic> post) =>
    ((post['image_urls'] as List?) ?? const []).length;

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
    // Discovery (discover_posts) is authenticated-only; an anonymous viewer
    // would just 403. Prompt them to sign in instead of showing an error.
    if (ref.watch(isAnonymousProvider)) {
      return const AdaptiveScaffold(title: 'Discover', body: _SignInToDiscover());
    }

    // Centre the feed on the user's saved home base once it loads (unless they
    // have already picked an anchor this session).
    ref.listen(homeLocationProvider, (_, next) {
      final home = next.value;
      if (home != null) {
        ref.read(anchorProvider.notifier).adoptHome(home.lat, home.lng);
      }
    });

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

class _SignInToDiscover extends StatelessWidget {
  const _SignInToDiscover();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_outlined, size: 48, color: Color(0xFF0F6E56)),
            const SizedBox(height: 16),
            Text(
              'Discover games and players near you',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to post a looking-for ad, reply to teams nearby, and message players.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.push(Routes.signIn),
              child: const Text('Sign in'),
            ),
          ],
        ),
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
              if (_imageCount(post) > 0 || (post['link_url'] as String?) != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_imageCount(post) > 0) ...[
                      const Icon(Icons.photo_outlined, size: 16),
                      const SizedBox(width: 4),
                      Text('${_imageCount(post)}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 12),
                    ],
                    if ((post['link_url'] as String?) != null)
                      const Icon(Icons.link, size: 16),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
