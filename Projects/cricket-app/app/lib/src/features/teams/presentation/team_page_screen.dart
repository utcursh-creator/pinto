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
                  // TEAM-13: the career line - the team is no longer a shell.
                  _TeamRecordLine(teamId: teamId),
                  // TEAM-11: a signed-in stranger can ask to join.
                  if (uid != null && myRow == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: FilledButton.icon(
                        onPressed: () => _requestToJoin(context, ref),
                        icon: const Icon(Icons.group_add_outlined),
                        label: const Text('Request to join'),
                      ),
                    ),
                  // TEAM-11: admins act on pending join requests inline.
                  if (isAdmin) _JoinRequests(teamId: teamId),
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
                      // STAT-2: everyone has a career page now - registered
                      // members by profile id, guests by their member id.
                      onOpenStats: member['profile_id'] == null
                          ? () => context.push(
                                Routes.guestPlayerStats(member['id'] as String),
                              )
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
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _invitePlayer(context, ref),
                        icon: const Icon(Icons.link),
                        label: const Text('Invite a player'),
                      ),
                    ),
                  if (isAdmin)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: OutlinedButton.icon(
                        onPressed: () => _manageInvites(context, ref),
                        icon: const Icon(Icons.link_off),
                        label: const Text('Manage invites'),
                      ),
                    ),
                  const Divider(height: 1),
                  _HomeGround(teamId: teamId, isAdmin: isAdmin),
                  const Divider(height: 1),
                  // TEAM-13: recent matches, tap through to the scorecard.
                  _TeamMatches(teamId: teamId),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// TEAM-11: send a join request (admin gets a notification).
  Future<void> _requestToJoin(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(identityRepositoryProvider).requestToJoin(teamId);
      messenger?.showSnackBar(const SnackBar(
          content: Text('Request sent - the captain will review it')));
    } catch (e) {
      final raw = '$e';
      messenger?.showSnackBar(SnackBar(
          content: Text(raw.contains('already pending')
              ? 'Your request is already pending.'
              : raw.contains('already on this team')
                  ? 'You are already on this team.'
                  : 'Could not send the request: $raw')));
    }
  }

  /// TEAM-3/MISS-6: list outstanding invites with uses/expiry and revoke.
  Future<void> _manageInvites(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Consumer(builder: (ctx, sheetRef, _) {
          final invites = sheetRef.watch(activeTeamInvitesProvider(teamId));
          return invites.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator.adaptive())),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load invites.\n$e')),
            data: (rows) => rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No active invites.'))
                : ListView(
                    shrinkWrap: true,
                    children: [
                      const ListTile(title: Text('Active invites')),
                      for (final i in rows)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.link, size: 20),
                          title: Text('Used ${i['uses'] ?? 0}'
                              '${i['max_uses'] != null ? ' of ${i['max_uses']}' : ''} times'),
                          subtitle: Text(
                              'Expires ${(i['expires_at'] as String?)?.split('T').first ?? '-'}'),
                          trailing: TextButton(
                            onPressed: () async {
                              final messenger =
                                  ScaffoldMessenger.maybeOf(context);
                              try {
                                await sheetRef
                                    .read(identityRepositoryProvider)
                                    .revokeInvite(i['id'] as String);
                                sheetRef.invalidate(
                                    activeTeamInvitesProvider(teamId));
                              } catch (e) {
                                // fresh-eyes audit: a failed revoke left the
                                // invite alive with zero feedback
                                messenger?.showSnackBar(SnackBar(
                                    content: Text('Could not revoke: $e')));
                              }
                            },
                            child: const Text('Revoke',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ),
                    ],
                  ),
          );
        }),
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
          // MTCH-4: a team with match/tournament history is FK-protected -
          // translate the raw violation into a human sentence.
          final raw = '$e';
          messenger?.showSnackBar(SnackBar(
              content: Text(raw.contains('foreign key') || raw.contains('23503')
                  ? 'This team has match history and cannot be deleted. '
                      'You can leave it instead.'
                  : 'Could not delete: $raw')));
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

  /// TEAM-1/5: per-member admin actions (remove, change role). Guard: never
  /// demote or remove the LAST captain - a team must keep at least one.
  Future<void> _memberAction(BuildContext context, WidgetRef ref, String action,
      Map<String, dynamic> member) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = ref.read(identityRepositoryProvider);
    // TEAM-5: last-captain guard (audit: the old comment claimed a guard that
    // did not exist).
    if (member['role'] == 'captain' && action != 'captain') {
      final roster = ref.read(teamRosterProvider(teamId)).value ?? const [];
      final captains = roster.where((r) => r['role'] == 'captain').length;
      if (captains <= 1) {
        messenger?.showSnackBar(const SnackBar(
            content: Text('A team needs at least one captain - '
                'make someone else captain first.')));
        return;
      }
    }
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
    try {
      await ref
          .read(identityRepositoryProvider)
          .addGuest(teamId: teamId, guestName: name);
      ref.invalidate(teamRosterProvider(teamId));
    } catch (e) {
      // TEAM-6: the server now raises friendly errors (empty name, duplicate
      // guest) - surface them instead of throwing an unhandled exception.
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Could not add guest: $e')));
      }
    }
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
    // TEAM-8: capture a human ground name so it never reads "Saved location".
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Home ground'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Ground name', hintText: 'e.g. Shivaji Park'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Use my location')),
        ],
      ),
    );
    if (name == null) return;
    if (!context.mounted) return;
    try {
      final pos = await ref.read(locationServiceProvider).current();
      await ref
          .read(discoverRepositoryProvider)
          .setTeamLocation(teamId, pos.lat, pos.lng,
              label: name.isEmpty ? null : name);
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

/// TEAM-13: "P 4 - W 2, L 1, T 1" off team_career_stats.
class _TeamRecordLine extends ConsumerWidget {
  const _TeamRecordLine({required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(teamStatsProvider(teamId)).value;
    if (stats == null) return const SizedBox.shrink();
    final played = (stats['played'] as num?)?.toInt() ?? 0;
    if (played == 0) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Text('No completed matches yet.',
            style: TextStyle(color: Colors.black54, fontSize: 13)),
      );
    }
    final w = (stats['won'] as num?)?.toInt() ?? 0;
    final l = (stats['lost'] as num?)?.toInt() ?? 0;
    final t = (stats['tied'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Text(
        'Played $played  -  Won $w, Lost $l${t > 0 ? ', Tied $t' : ''}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

/// TEAM-11: pending join requests, approve/decline inline (admins only).
class _JoinRequests extends ConsumerWidget {
  const _JoinRequests({required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(pendingJoinRequestsProvider(teamId)).value ??
        const <Map<String, dynamic>>[];
    if (requests.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text('Join requests',
              style: TextStyle(fontWeight: FontWeight.w500)),
        ),
        for (final r in requests)
          ListTile(
            dense: true,
            leading: InitialsAvatar(
              name: (r['profiles'] as Map?)?['display_name'] as String?,
              photoUrl: (r['profiles'] as Map?)?['photo_url'] as String?,
              radius: 18,
            ),
            title: Text(
                ((r['profiles'] as Map?)?['display_name'] as String?) ??
                    'Player'),
            trailing: Wrap(spacing: 4, children: [
              TextButton(
                onPressed: () => _respond(ref, r['id'] as String, true),
                child: const Text('Approve'),
              ),
              TextButton(
                onPressed: () => _respond(ref, r['id'] as String, false),
                child: const Text('Decline',
                    style: TextStyle(color: Colors.red)),
              ),
            ]),
          ),
      ],
    );
  }

  Future<void> _respond(WidgetRef ref, String requestId, bool approve) async {
    try {
      await ref
          .read(identityRepositoryProvider)
          .respondJoinRequest(requestId, approve);
      ref.invalidate(pendingJoinRequestsProvider(teamId));
      if (approve) ref.invalidate(teamRosterProvider(teamId));
    } catch (_) {/* the list refresh reflects reality */}
  }
}

/// TEAM-13: the team's recent matches, tap-through to the scorecard.
class _TeamMatches extends ConsumerWidget {
  const _TeamMatches({required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(teamMatchesProvider(teamId)).value ??
        const <Map<String, dynamic>>[];
    if (matches.isEmpty) return const SizedBox.shrink();
    String name(dynamic embed) =>
        (embed is Map ? embed['name'] as String? : null) ?? 'Team';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('Matches',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        for (final m in matches)
          ListTile(
            dense: true,
            leading: Icon(
              m['status'] == 'complete' ? Icons.emoji_events_outlined : Icons.sensors,
              size: 20,
              color: m['status'] == 'live' ? Colors.red : null,
            ),
            title: Text('${name(m['team_a'])}  v  ${name(m['team_b'])}'),
            subtitle: Text(
              (m['result'] is Map ? (m['result'] as Map)['note'] as String? : null) ??
                  (m['status'] == 'live' ? 'Live now' : 'In progress'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => context.push(Routes.viewMatch(m['id'] as String)),
          ),
      ],
    );
  }
}
