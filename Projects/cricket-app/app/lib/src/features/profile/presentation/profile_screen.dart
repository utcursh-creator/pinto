import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/profile_provider.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/platform/error_retry.dart';
import '../../../core/routing/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../identity/data/identity_labels.dart';
import '../../identity/presentation/initials_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    return AdaptiveScaffold(
      title: 'Profile',
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        // PROF-3: never dump a raw error - friendly line + Retry
        error: (e, _) => ErrorRetry(
          message: 'Could not load your profile.',
          detail: e,
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
        data: (profile) {
          if (profile == null) {
            // PROF-5: the anonymous tab is a doorway, not a wall - browse the
            // public side of the app and sign in when ready.
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 24),
                const Icon(Icons.sports_cricket, size: 48),
                const SizedBox(height: 12),
                Text('Pitch works without an account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  'Watch live matches and follow tournaments as a guest. '
                  'Sign in to build a team, post in Discover and score matches.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.push(Routes.signIn),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: 16),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.sensors),
                  title: const Text('Watch live matches'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.liveMatches),
                ),
                ListTile(
                  leading: const Icon(Icons.search),
                  title: const Text('Find players and teams'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.search),
                ),
              ],
            );
          }
          return RefreshIndicator.adaptive(
            onRefresh: () async => ref.invalidate(myProfileProvider),
            child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    InitialsAvatar(
                      name: profile['display_name'] as String?,
                      photoUrl: profile['photo_url'] as String?,
                      radius: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (profile['display_name'] as String?) ?? 'Player',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          // MISS-5: the handle is your address - show it
                          if ((profile['handle'] as String?)?.isNotEmpty ??
                              false)
                            Text(
                              '@${profile['handle']}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF0F6E56)),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            IdentityLabels.profileSubtitle(profile),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.bar_chart_outlined),
                title: const Text('My cricket'),
                subtitle: const Text('Career batting, bowling and fielding'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.push(Routes.playerStats(profile['id'] as String)),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit profile'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.editProfile),
              ),
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('My teams'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.myTeams),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.settings),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: OutlinedButton(
                  onPressed: () => _confirmSignOut(context, ref),
                  child: const Text('Sign out'),
                ),
              ),
            ],
            ),
          );
        },
      ),
    );
  }

  // AUTH-7: confirm, then sign out with feedback (the anon-bootstrap listener
  // re-establishes a guest session, so the router drops back to Discover).
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You can keep browsing as a guest and sign back in anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(supabaseClientProvider).auth.signOut();
      messenger.showSnackBar(const SnackBar(content: Text('Signed out')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not sign out. Please try again.')),
      );
    }
  }
}
