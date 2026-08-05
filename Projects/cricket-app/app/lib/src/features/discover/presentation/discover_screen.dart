import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/platform/error_retry.dart';
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

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with WidgetsBindingObserver {
  String? _mode;
  String? _flair;
  String? _skill;
  int? _maxOvers;
  DateTime? _fromDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user channel carries the badges live, but the OS tears the socket
    // down on a locked phone and does not always re-subscribe. A phone that
    // slept through a conversation must catch up when it wakes (review #3).
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(dmInboxProvider);
    ref.invalidate(notificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Discovery (discover_posts) is authenticated-only; an anonymous viewer
    // would just 403. Prompt them to sign in instead of showing an error.
    if (ref.watch(isAnonymousProvider)) {
      return const AdaptiveScaffold(title: 'Discover', body: _SignInToDiscover());
    }

    // Derived purely from two watched values - no provider watches another, so
    // nothing can invalidate itself mid-build (see discover_providers.dart).
    final chosenAnchor = ref.watch(anchorProvider);
    final homeRead = ref.watch(homeLocationProvider);
    // Error and "not set" both arrive as a null `.value`, so the feed silently
    // pinned itself to a fallback city with nothing said (review #2, finding
    // 70). Guessing is fine; guessing silently is not.
    final guessingLocation = chosenAnchor == null && homeRead.hasError;
    final anchor = effectiveAnchor(chosenAnchor, homeRead.value);
    final query = DiscoverQuery(
      lat: anchor.lat,
      lng: anchor.lng,
      radiusM: anchor.radiusM,
      mode: _mode,
      flair: _flair,
      skill: _skill,
      maxOvers: _maxOvers,
      onOrAfter: _fromDate,
    );
    final feed = ref.watch(discoverFeedProvider(query));
    final cupertino = isCupertino(context);

    return AdaptiveScaffold(
      title: 'Discover',
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search players & teams',
          onPressed: () => context.push(Routes.search),
        ),
        IconButton(
          icon: _Badged(
            count: unreadNotificationCount(
                ref.watch(notificationsProvider).value),
            dotKey: const Key('badge_bell'),
            child: const Icon(Icons.notifications_none),
          ),
          tooltip: 'Notifications',
          onPressed: () => context.push(Routes.notifications),
        ),
        IconButton(
          icon: _Badged(
            count: unreadDmCount(ref.watch(dmInboxProvider).value),
            dotKey: const Key('badge_mail'),
            child: const Icon(Icons.mail_outline),
          ),
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
          // Guessing is fine; guessing SILENTLY is not. Without this the feed
          // showed another city's games with nothing to indicate it, and the
          // only recovery was to reopen Location and re-save by hand.
          if (guessingLocation)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF3CD),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'We could not read your home ground, so these are games '
                      'near a default city.',
                      style: TextStyle(color: Color(0xFF8A6D00)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(homeLocationProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          _FilterBar(
            mode: _mode,
            flair: _flair,
            skill: _skill,
            maxOvers: _maxOvers,
            fromDate: _fromDate,
            onMode: (m) => setState(() => _mode = m),
            onFlair: (f) => setState(() => _flair = f),
            onSkill: (s) => setState(() => _skill = s),
            onMaxOvers: (o) => setState(() => _maxOvers = o),
            onFromDate: (d) => setState(() => _fromDate = d),
            onLocation: () => context.push(Routes.location),
          ),
          Expanded(
            child: feed.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              // PROF-3: friendly error + Retry, never a raw dump
              error: (e, _) => ErrorRetry(
                message: 'Could not load the feed.',
                detail: e,
                onRetry: () {
                  // the home ground read is what failed first; retrying only
                  // the feed keeps the wrong anchor forever
                  ref.invalidate(homeLocationProvider);
                  ref.invalidate(discoverFeedProvider(query));
                },
              ),
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
    required this.skill,
    required this.maxOvers,
    required this.fromDate,
    required this.onMode,
    required this.onFlair,
    required this.onSkill,
    required this.onMaxOvers,
    required this.onFromDate,
    required this.onLocation,
  });

  final String? mode;
  final String? flair;
  final String? skill;
  final int? maxOvers;
  final DateTime? fromDate;
  final ValueChanged<String?> onMode;
  final ValueChanged<String?> onFlair;
  final ValueChanged<String?> onSkill;
  final ValueChanged<int?> onMaxOvers;
  final ValueChanged<DateTime?> onFromDate;
  final VoidCallback onLocation;

  Future<void> _pickFromDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: fromDate ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) onFromDate(picked);
  }

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
          // DISC-3: skill / overs-cap / from-date filters (the RPC already
          // supported _skill/_max_overs/_on_or_after; this row finally sends them).
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in LfLabels.skills.entries) ...[
                  ChoiceChip(
                    label: Text(e.value),
                    selected: skill == e.key,
                    onSelected: (v) => onSkill(v ? e.key : null),
                  ),
                  const SizedBox(width: 6),
                ],
                for (final cap in const [10, 20, 30]) ...[
                  ChoiceChip(
                    label: Text('<= $cap ov'),
                    selected: maxOvers == cap,
                    onSelected: (v) => onMaxOvers(v ? cap : null),
                  ),
                  const SizedBox(width: 6),
                ],
                FilterChip(
                  avatar: const Icon(Icons.event, size: 16),
                  label: Text(fromDate == null
                      ? 'From date'
                      : '${fromDate!.day}/${fromDate!.month}'),
                  selected: fromDate != null,
                  onSelected: (v) =>
                      v ? _pickFromDate(context) : onFromDate(null),
                ),
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
    final rawTitle = post['title'] as String?;
    final hasTitle = rawTitle != null && rawTitle.trim().isNotEmpty;
    final title = hasTitle ? rawTitle : LfLabels.mode(post['mode'] as String?);
    final desc = post['description'] as String?;
    final author = post['author_name'] as String?;
    final team = post['team_name'] as String?;
    final chips = LfLabels.metaChips(
      overs: (post['overs'] as num?)?.toInt(),
      skillLevel: post['skill'] as String?,
      slotsNeeded: (post['slots_needed'] as num?)?.toInt(),
      matchAt: post['match_at'],
      ballType: post['ball_type'] as String?, // DISC-1
    );
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
                  // DISC-6: only show the mode label here when it isn't already
                  // the title, so it never renders twice.
                  if (hasTitle) ...[
                    const SizedBox(width: 8),
                    Text(
                      LfLabels.mode(post['mode'] as String?),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
              // DISC-5: who posted it (and their team).
              if (author != null && author.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Posted by $author${team != null && team.isNotEmpty ? ' ($team)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              // DISC-2: the cricket metadata chips.
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final c in chips) _MetaChip(c)],
                ),
              ],
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

/// A small pill for a post's cricket metadata (overs / skill / slots / when).
class _MetaChip extends StatelessWidget {
  const _MetaChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

/// A small unread-count dot over an app-bar icon (DM-4 / MISS-2 badges).
class _Badged extends StatelessWidget {
  const _Badged({required this.count, required this.child, this.dotKey});
  final int count;
  final Widget child;

  /// Keys the DOT, not the icon: the dot only exists when count > 0, so a test
  /// asking for it is asking the question a person asks - "is there a badge?" -
  /// and not "is there an icon that might have one".
  final Key? dotKey;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            key: dotKey,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFD7263D),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(minWidth: 14),
            child: Text(
              count > 9 ? '9+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
