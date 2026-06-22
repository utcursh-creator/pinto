import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../identity/data/identity_providers.dart';
import '../../identity/data/identity_repository.dart';

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
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('$name approved')));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(e.message)));
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
        error: (e, _) => Center(child: Text('Could not load requests.\n$e')),
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
              final claimer =
                  (r['requester'] as Map<String, dynamic>?)?['display_name']
                          as String? ??
                      'A player';
              final membershipId = r['membership_id'] as String;
              final claimerId = r['requested_by'] as String;
              final busy = _busyId == membershipId;
              return ListTile(
                title: Text('$claimer wants to claim "$guestName"'),
                subtitle: Text('on $teamName'),
                trailing: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                      )
                    : FilledButton(
                        onPressed: () =>
                            _approve(membershipId, claimerId, claimer),
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
