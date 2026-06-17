import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/profile_provider.dart';
import '../../../core/platform/adaptive_scaffold.dart';
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
        error: (e, _) => Center(child: Text('Could not load profile.\n$e')),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('No profile yet.'));
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    InitialsAvatar(
                      name: profile['display_name'] as String?,
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
              const ListTile(
                leading: Icon(Icons.settings_outlined),
                title: Text('Settings'),
                trailing: Icon(Icons.chevron_right),
                enabled: false,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: OutlinedButton(
                  onPressed: () =>
                      ref.read(supabaseClientProvider).auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
