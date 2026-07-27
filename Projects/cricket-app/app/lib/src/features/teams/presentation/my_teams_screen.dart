import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../identity/data/identity_labels.dart';
import '../../identity/data/identity_providers.dart';
import '../../identity/presentation/initials_avatar.dart';
import '../../../core/ui/human_error.dart';

/// Pulls the token out of whatever the user pasted. People paste the whole
/// link far more often than the bare code, so accept both.
String inviteTokenFrom(String input) {
  final t = input.trim();
  if (t.isEmpty) return '';
  final marker = t.lastIndexOf('/invite/');
  final tail = marker >= 0 ? t.substring(marker + '/invite/'.length) : t;
  // drop any query/fragment a chat client may have appended
  return tail.split(RegExp(r'[?#\s]')).first.trim();
}

Future<void> _promptForInviteCode(BuildContext context) async {
  final controller = TextEditingController();
  final token = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Join a team'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Paste the invite code or the whole link your captain '
              'sent you.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Invite code or link',
              hintText: 'pitch.app/invite/...',
            ),
            onSubmitted: (v) =>
                Navigator.of(dialogContext).pop(inviteTokenFrom(v)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext)
              .pop(inviteTokenFrom(controller.text)),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (token == null || token.isEmpty || !context.mounted) return;
  context.push(Routes.acceptInvite(token));
}

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
        error: (e, _) => Center(child: Text(humanError(e, fallback: 'Could not load teams.'))),
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
              // A captain shares an invite as a https://pitch.app/invite/<token>
              // link, but that domain is not registered for deep links yet, so
              // the recipient taps it and lands in a browser on nothing. Until
              // it is, they need a way to redeem the code by hand - otherwise
              // every invite the app sends is a dead end.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: OutlinedButton.icon(
                  onPressed: () => _promptForInviteCode(context),
                  icon: const Icon(Icons.link),
                  label: const Text('Have an invite code?'),
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
