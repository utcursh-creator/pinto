import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../identity/data/identity_labels.dart';
import '../../identity/data/identity_providers.dart';
import '../../identity/presentation/initials_avatar.dart';

class MyTeamsScreen extends ConsumerWidget {
  const MyTeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(myTeamsProvider);
    return AdaptiveScaffold(
      title: 'My teams',
      actions: [
        IconButton(
          icon: const Icon(Icons.how_to_reg_outlined),
          tooltip: 'Claim requests',
          onPressed: () => context.push(Routes.claimInbox),
        ),
      ],
      body: teamsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Could not load teams.\n$e')),
        data: (rows) {
          return RefreshIndicator.adaptive(
            // TEAM-12: pull-to-refresh (stale after invite-accept/leave).
            onRefresh: () async => ref.invalidate(myTeamsProvider),
            child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text("You're not on any teams yet."),
                  ),
                ),
              // TEAM-12: null-guard the embed (a deleted team leaves the row).
              for (final row in rows)
                if (row['teams'] is Map)
                  _TeamTile(
                    team: (row['teams'] as Map).cast<String, dynamic>(),
                    role: row['role'] as String?,
                  ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: FilledButton.icon(
                  onPressed: () => context.push(Routes.createTeam),
                  icon: const Icon(Icons.add),
                  label: const Text('Create team'),
                ),
              ),
            ],
          ),
          );
        },
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({required this.team, required this.role});

  final Map<String, dynamic> team;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final city = team['city'] as String?;
    return ListTile(
      leading: InitialsAvatar(name: team['name'] as String?, radius: 20),
      title: Text((team['name'] as String?) ?? 'Team'),
      subtitle: (city != null && city.isNotEmpty) ? Text(city) : null,
      trailing: Chip(label: Text(IdentityLabels.teamRole(role))),
      onTap: () => context.push(Routes.teamPage(team['id'] as String)),
    );
  }
}
