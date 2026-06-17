import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../identity/data/identity_labels.dart';
import '../../identity/data/identity_providers.dart';
import '../../identity/data/identity_repository.dart';
import '../../identity/presentation/initials_avatar.dart';

class TeamPageScreen extends ConsumerWidget {
  const TeamPageScreen({required this.teamId, super.key});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamProvider(teamId));
    final rosterAsync = ref.watch(teamRosterProvider(teamId));
    final uid = ref.watch(currentSessionProvider)?.user.id;
    final team = teamAsync.value;

    return AdaptiveScaffold(
      title: (team?['name'] as String?) ?? 'Team',
      body: teamAsync.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Could not load team.\n$e')),
        data: (team) {
          if (team == null) return const Center(child: Text('Team not found.'));
          final city = team['city'] as String?;
          return rosterAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator.adaptive()),
            error: (e, _) => Center(child: Text('Could not load roster.\n$e')),
            data: (roster) {
              Map<String, dynamic>? myRow;
              for (final r in roster) {
                if (r['profile_id'] == uid) myRow = r;
              }
              final isAdmin = myRow != null &&
                  (myRow['role'] == 'captain' || myRow['role'] == 'admin');

              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        InitialsAvatar(name: team['name'] as String?, radius: 28),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (team['name'] as String?) ?? 'Team',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (city != null && city.isNotEmpty)
                                Text(
                                  city,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(
                      'Members (${roster.length})',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  for (final member in roster) _MemberTile(member: member),
                  if (isAdmin)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: OutlinedButton.icon(
                        onPressed: () => _addGuest(context, ref),
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Add guest player'),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addGuest(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add guest player'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Guest name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref
        .read(identityRepositoryProvider)
        .addGuest(teamId: teamId, guestName: name);
    ref.invalidate(teamRosterProvider(teamId));
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final profile = member['profiles'] as Map<String, dynamic>?;
    final isGuest = member['profile_id'] == null;
    final name = isGuest
        ? (member['guest_name'] as String?) ?? 'Guest'
        : (profile?['display_name'] as String?) ?? 'Player';
    return ListTile(
      leading: InitialsAvatar(name: name, radius: 18),
      title: Text(name),
      subtitle: isGuest ? const Text('Guest') : null,
      trailing: Text(IdentityLabels.teamRole(member['role'] as String?)),
    );
  }
}
