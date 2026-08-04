import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../identity/data/identity_providers.dart';
import '../../identity/data/identity_repository.dart';
import '../../identity/presentation/initials_avatar.dart';
import '../../../core/ui/human_error.dart';
import '../../../core/platform/error_retry.dart';

/// Captain inbox: pending requests from registered players to take over a guest
/// roster spot. Approving transfers that guest membership (and its history) to
/// the claimer.
class ClaimInboxScreen extends ConsumerStatefulWidget {
  const ClaimInboxScreen({super.key});

  @override
  ConsumerState<ClaimInboxScreen> createState() => _ClaimInboxScreenState();
}

class _ClaimInboxScreenState extends ConsumerState<ClaimInboxScreen> {
  String? _busyId;

  Future<void> _approve(String membershipId, String claimerId, String name) async {
    setState(() => _busyId = membershipId);
    try {
      await ref.read(identityRepositoryProvider).approveGuestClaim(
            membershipId: membershipId,
            claimerId: claimerId,
          );
      ref.invalidate(claimInboxProvider);
      // Approving a claim rewrites the membership row, so any team page still
      // in the stack keeps showing the guest with its "This is me" button until
      // it is rebuilt. The whole family, because this inbox spans every team
      // the captain runs and the claim does not say which one is on screen
      // (review #2, finding 71).
      ref.invalidate(teamRosterProvider);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('$name approved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(humanError(e))));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(claimInboxProvider);
    return AdaptiveScaffold(
      title: 'Claim requests',
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => ErrorRetry(
          message: humanError(e, fallback: 'Could not load requests.'),
          onRetry: () => ref.invalidate(claimInboxProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No pending claim requests on your teams.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = rows[i];
              final tm = r['team_members'] as Map<String, dynamic>?;
              final teamName =
                  (tm?['teams'] as Map<String, dynamic>?)?['name'] as String? ??
                      'a team';
              final guestName = tm?['guest_name'] as String? ?? 'a guest';
              final requester = r['requester'] as Map<String, dynamic>?;
              // TEAM-9: never blind-approve - a claimer whose profile cannot
              // be resolved shows as unknown and cannot be approved.
              final known = requester?['display_name'] != null;
              final claimer =
                  (requester?['display_name'] as String?) ?? 'Unknown player';
              final membershipId = r['membership_id'] as String;
              final claimerId = r['requested_by'] as String;
              final busy = _busyId == membershipId;
              return ListTile(
                leading: InitialsAvatar(
                  name: claimer,
                  photoUrl: requester?['photo_url'] as String?,
                  radius: 20,
                ),
                title: Text('$claimer wants to claim "$guestName"'),
                subtitle: Text(known
                    ? 'on $teamName'
                    : 'on $teamName - profile unavailable, cannot approve'),
                trailing: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                      )
                    : FilledButton(
                        onPressed: known
                            ? () => _approve(membershipId, claimerId, claimer)
                            : null,
                        child: const Text('Approve'),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
