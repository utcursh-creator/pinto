import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../discover/data/discover_providers.dart';
import '../../discover/data/discover_repository.dart';
import '../../discover/data/location_service.dart';
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

    // TEAM-1: leave/delete/edit live in the app-bar overflow, gated by the
    // viewer's own membership row.
    Map<String, dynamic>? myRow;
    for (final r in rosterAsync.value ?? const <Map<String, dynamic>>[]) {
      if (r['profile_id'] == uid) myRow = r;
    }
    final myIsAdmin =
        myRow != null && (myRow['role'] == 'captain' || myRow['role'] == 'admin');

    return AdaptiveScaffold(
      title: (team?['name'] as String?) ?? 'Team',
      actions: [
        if (myRow != null)
          PopupMenuButton<String>(
            key: const Key('team_menu'),
            onSelected: (v) => _teamAction(context, ref, v, myRow!),
            itemBuilder: (context) => [
              if (myIsAdmin)
                const PopupMenuItem(value: 'edit', child: Text('Edit team')),
              const PopupMenuItem(value: 'leave', child: Text('Leave team')),
              if (myIsAdmin)
                const PopupMenuItem(value: 'delete', child: Text('Delete team')),
            ],
          ),
      ],
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
                        GestureDetector(
                          onTap: isAdmin
                              ? () => _changeLogo(context, ref)
                              : null,
                          child: InitialsAvatar(
                            name: team['name'] as String?,
                            photoUrl: team['logo_url'] as String?,
                            radius: 28,
                          ),
                        ),
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
                  for (final member in roster)
                    _MemberTile(
                      member: member,
                      // TEAM-1/5: an admin can remove members + change roles
                      // (not on their own row - they use Leave team for that).
                      adminMenu: isAdmin && member['profile_id'] != uid,
                      onMemberAction: (v) =>
                          _memberAction(context, ref, v, member),
                      onClaim: (uid != null && member['profile_id'] == null)
                          ? () => _claim(context, ref, member['id'] as String)
                          : null,
                      // Registered members have a public stats page; guests do
                      // not until they are claimed.
                      onOpenStats: member['profile_id'] == null
                          ? null
                          : () => context.push(
                                Routes.playerStats(member['profile_id'] as String),
                              ),
                    ),
                  if (isAdmin)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _addGuest(context, ref),
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Add guest player'),
                      ),
                    ),
                  if (isAdmin)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: OutlinedButton.icon(
                        onPressed: () => _invitePlayer(context, ref),
                        icon: const Icon(Icons.link),
                        label: const Text('Invite a player'),
                      ),
                    ),
                  const Divider(height: 1),
                  _HomeGround(teamId: teamId, isAdmin: isAdmin),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// TEAM-1/13: leave / delete / edit from the app-bar overflow.
  Future<void> _teamAction(BuildContext context, WidgetRef ref, String action,
      Map<String, dynamic> myRow) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = ref.read(identityRepositoryProvider);
    switch (action) {
      case 'leave':
        final ok = await _confirm(context, 'Leave this team?',
            'You will be removed from the roster.', 'Leave');
        if (ok != true || !context.mounted) return;
        try {
          await repo.removeMember(myRow['id'] as String);
          ref.invalidate(myTeamsProvider);
          ref.invalidate(teamRosterProvider(teamId));
          messenger
              ?.showSnackBar(const SnackBar(content: Text('You left the team')));
          if (context.mounted) context.pop();
        } catch (e) {
          messenger?.showSnackBar(SnackBar(content: Text('Could not leave: $e')));
        }
      case 'delete':
        final ok = await _confirm(context, 'Delete this team?',
            'The team and its roster are permanently removed.', 'Delete',
            destructive: true);
        if (ok != true || !context.mounted) return;
        try {
          await repo.deleteTeam(teamId);
          ref.invalidate(myTeamsProvider);
          messenger
              ?.showSnackBar(const SnackBar(content: Text('Team deleted')));
          if (context.mounted) context.pop();
        } catch (e) {
          messenger?.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
        }
      case 'edit':
        await _editTeam(context, ref);
    }
  }

  /// TEAM-13 (edit part): rename the team / change its city.
  Future<void> _editTeam(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final team = ref.read(teamProvider(teamId)).value;
    final name = TextEditingController(text: (team?['name'] as String?) ?? '');
    final city = TextEditingController(text: (team?['city'] as String?) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(
                controller: city,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'City')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(identityRepositoryProvider).updateTeam(teamId,
          name: name.text.trim(), city: city.text.trim());
      ref.invalidate(teamProvider(teamId));
      ref.invalidate(myTeamsProvider);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  /// TEAM-1/5: per-member admin actions (remove, change role). A guard keeps at
  /// least one captain: promoting someone to captain is always safe; demoting is
  /// only offered on non-captain rows here (the admin edits others, not self).
  Future<void> _memberAction(BuildContext context, WidgetRef ref, String action,
      Map<String, dynamic> member) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = ref.read(identityRepositoryProvider);
    try {
      switch (action) {
        case 'remove':
          final ok = await _confirm(context, 'Remove this player?',
              'They will be taken off the roster.', 'Remove',
              destructive: true);
          if (ok != true) return;
          await repo.removeMember(member['id'] as String);
        case 'captain':
        case 'admin':
        case 'player':
          await repo.setMemberRole(member['id'] as String, action);
      }
      ref.invalidate(teamRosterProvider(teamId));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<bool?> _confirm(
      BuildContext context, String title, String body, String action,
      {bool destructive = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: Colors.red)
                : null,
            child: Text(action),
          ),
        ],
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

  Future<void> _changeLogo(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1024);
    if (picked == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final repo = ref.read(identityRepositoryProvider);
      final url = await repo.uploadAvatar(bytes, picked.name.split('.').last);
      await repo.setTeamLogo(teamId, url);
      ref.invalidate(teamProvider(teamId));
      messenger?.showSnackBar(const SnackBar(content: Text('Logo updated')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _invitePlayer(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final token =
          await ref.read(identityRepositoryProvider).createTeamInvite(teamId);
      await SharePlus.instance.share(
        ShareParams(
          text: 'Join my cricket team on Pitch: ${inviteLink(token)}',
          subject: 'Pitch team invite',
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _claim(
    BuildContext context,
    WidgetRef ref,
    String membershipId,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(identityRepositoryProvider)
          .requestGuestClaim(membershipId);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Claim request sent to the captain')),
      );
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    this.adminMenu = false,
    this.onMemberAction,
    this.onClaim,
    this.onOpenStats,
  });

  final Map<String, dynamic> member;

  /// TEAM-1/5: when true, the viewer administers this team and this is not
  /// their own row - offer remove + role changes.
  final bool adminMenu;
  final ValueChanged<String>? onMemberAction;

  /// When set (a signed-in viewer looking at a guest row), offers "This is me".
  final VoidCallback? onClaim;

  /// When set (a registered member), tapping the row opens their stats page.
  final VoidCallback? onOpenStats;

  @override
  Widget build(BuildContext context) {
    final profile = member['profiles'] as Map<String, dynamic>?;
    final isGuest = member['profile_id'] == null;
    final role = member['role'] as String?;
    final name = isGuest
        ? (member['guest_name'] as String?) ?? 'Guest'
        : (profile?['display_name'] as String?) ?? 'Player';
    // TEAM-5: (C)/(A) badges inline with the name.
    final badge = switch (role) {
      'captain' => '  (C)',
      'admin' => '  (A)',
      _ => '',
    };
    Widget? trailing;
    if (onClaim != null) {
      trailing =
          TextButton(onPressed: onClaim, child: const Text('This is me'));
    } else if (adminMenu && onMemberAction != null) {
      trailing = PopupMenuButton<String>(
        key: Key('member_menu_${member['id']}'),
        onSelected: onMemberAction,
        itemBuilder: (context) => [
          // guests have no account, so roles apply to registered members only
          if (!isGuest && role != 'captain')
            const PopupMenuItem(value: 'captain', child: Text('Make captain')),
          if (!isGuest && role != 'admin')
            const PopupMenuItem(value: 'admin', child: Text('Make admin')),
          if (!isGuest && role != 'player')
            const PopupMenuItem(value: 'player', child: Text('Make player')),
          const PopupMenuItem(value: 'remove', child: Text('Remove from team')),
        ],
      );
    } else {
      trailing = Text(IdentityLabels.teamRole(role));
    }
    return ListTile(
      leading: InitialsAvatar(
        name: name,
        photoUrl: profile?['photo_url'] as String?,
        radius: 18,
      ),
      title: Text('$name$badge'),
      subtitle: isGuest ? const Text('Guest') : null,
      onTap: onOpenStats,
      trailing: trailing,
    );
  }
}

/// The team's home ground (geo). Members see it; admins can set it from GPS.
class _HomeGround extends ConsumerWidget {
  const _HomeGround({required this.teamId, required this.isAdmin});

  final String teamId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ground = ref.watch(teamGroundProvider(teamId));
    final label = ground.value?.label;
    final hasGround = ground.value != null;
    return ListTile(
      leading: const Icon(Icons.stadium_outlined),
      title: const Text('Home ground'),
      subtitle: Text(
        hasGround
            ? (label ?? 'Saved location')
            : isAdmin
                ? 'Not set - tap to use this location'
                : 'Not set',
      ),
      trailing: isAdmin ? const Icon(Icons.my_location) : null,
      onTap: isAdmin ? () => _setFromGps(context, ref) : null,
    );
  }

  Future<void> _setFromGps(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final pos = await ref.read(locationServiceProvider).current();
      await ref
          .read(discoverRepositoryProvider)
          .setTeamLocation(teamId, pos.lat, pos.lng);
      ref.invalidate(teamGroundProvider(teamId));
      messenger?.showSnackBar(
        const SnackBar(content: Text('Home ground saved')),
      );
    } on LocationException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
